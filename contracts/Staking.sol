// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./RewardPool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error Staking__NoStakeInPool();
error Staking__NoRewardsAvailable();
error Staking__UnbondingIncomplete(uint waitInSeconds);
error Staking__WithdrawLessThanYourBalance();
error Staking__PoolLimitReached(
    uint maxPoolSize,
    uint yourDeposit,
    int reduceBy
);
error Staking__PoolAlreadyClosed();
error Staking__PoolExceededValidityPeriod();
error Staking__StakeExceedsYourBalance();
error Staking__ZeroAddressNotAllowed();

contract StakingRewards is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    event Staked(
        address userAddress,
        uint amountStaked,
        uint userBalance,
        uint rewardBalance,
        uint totalSupplyStaked
    );
    event Unstaked(
        address userAddress,
        uint amountStaked,
        uint userBalance,
        uint rewardBalance,
        uint totalSupplyStaked
    );
    event RewardsClaimed(address userAddress, uint rewardsAmount);
    event ClosedPool(address sender, uint withdrawnFromPool);

    address public stakingTokenAddress;
    address public rewardPoolAddress;

    address public owner; // Contract owner
    uint public constant VALIDITY_PERIOD = 60 * 60 * 24 * 365; //Length of days for staking: 1 year
    uint public constant MAXIMUM_POOL_MONIONS = 500000;
    //  * 1e18; //Maximum Pool size for Staking
    uint public constant TOTAL_REWARD = 100000;
    //  * 1e18; //20% return on Max Pool size.

    uint public finishAt; //Time at which staking becomes closed. i.e. Current time + 1 year,

    bool public isPoolClosed; //Checker whether the pool will pay rewards or not.

    mapping(address => uint) public userToUnstakingTime; //Tracks unbonding time.
    mapping(address => bool) public unstakingFlagPerUser; //Tracks unstake state
    mapping(address => uint) public userLastUpdateTime; //Tracks the last time a user interacted with the contract.
    mapping(address => uint) public rewards; //Tracks user's rewards balance.
    mapping(address => uint) public balanceOf; //Tracks user's staked balance.

    /// @param _stakingToken This is the Address of the ERC20 token we are staking.
    /// @param _rewardPool This is the distributor contract that pays out rewards.
    constructor(address _stakingToken, address _rewardPool) ReentrancyGuard() {
        if (_stakingToken == address(0) || _rewardPool == address(0)) {
            revert Staking__ZeroAddressNotAllowed();
        }
        owner = msg.sender;
        stakingTokenAddress = _stakingToken;
        rewardPoolAddress = _rewardPool;
        finishAt = block.timestamp + VALIDITY_PERIOD; //Time after which staking is no longer permitted.
    }

    /// @notice Modifier to ensure only certain actions are taken by the owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    /// @notice Modifier to update a user's reward everytime a user interacts with the contract.
    modifier updateReward(address _account) {
        rewards[msg.sender] += _calcReward();
        userLastUpdateTime[msg.sender] = _lastTimeRewardApplicable();
        _;
    }

    /// @notice Modifier to ensure that no user stakes more than the pool can hold.
    modifier validateDeposit(uint amount) {
        require(_poolChecker(amount));
        _;
    }

    /// @dev This function allows users to stake their ERC20 tokens of specific type.
    /// @param amount This function allows users to stake an amount from their balance.
    /// @notice This function only works when the contract is not paused.
    /// @notice This function only allows the user to stake an amount less than the pool limit.
    function stake(uint amount)
        external
        whenNotPaused
        validateDeposit(amount)
        updateReward(msg.sender)
        nonReentrant
    {
        IERC20 stakingToken = IERC20(stakingTokenAddress);
        if (isPoolClosed) {
            revert Staking__PoolAlreadyClosed();
        }

        if (block.timestamp > finishAt) {
            revert Staking__PoolExceededValidityPeriod();
        }

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        balanceOf[msg.sender] += amount;

        emit Staked(
            msg.sender,
            amount,
            balanceOf[msg.sender],
            rewards[msg.sender],
            getStakedBalance()
        );
    }

    /// @dev This function allows users to unstake their ERC20 tokens of specific type.
    /// @param amount This function allows users to unstake an amount previously staked in the contract.
    /// @notice This function only works when the contract is not paused.
    /// @notice This function only allows the user to stake an amount less than the pool limit.
    /// @notice This function has a pre-requisite which is initiateUnstaking();
    function _unstake(uint amount)
        internal
        whenNotPaused
        updateReward(msg.sender)
        nonReentrant
    {
        IERC20 stakingToken = IERC20(stakingTokenAddress);
        if (balanceOf[msg.sender] - amount < 0) {
            revert Staking__WithdrawLessThanYourBalance();
        }
        balanceOf[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(
            msg.sender,
            amount,
            balanceOf[msg.sender],
            rewards[msg.sender],
            getStakedBalance()
        );
    }

    /// @dev This function MUST be called before unstaking
    /// @notice The function is a pre-requisite to unstake.
    function initiateUnstake(uint amount) external whenNotPaused {
        if (block.timestamp > finishAt) {
            _unstake(amount);
        } else {
            if (!unstakingFlagPerUser[msg.sender]) {
                userToUnstakingTime[msg.sender] = block.timestamp + 1 days;
                unstakingFlagPerUser[msg.sender] = true;
            } else if (block.timestamp > userToUnstakingTime[msg.sender]) {
                _unstake(amount);
                unstakingFlagPerUser[msg.sender] = false;
            } else {
                uint waitInSeconds = userToUnstakingTime[msg.sender] -
                    block.timestamp;
                revert Staking__UnbondingIncomplete(waitInSeconds);
            }
        }
    }

    /// @dev This function allows the user to clalim rewards.
    function claimRewards()
        external
        whenNotPaused
        updateReward(msg.sender)
        nonReentrant
    {
        if (rewards[msg.sender] <= 0) {
            revert Staking__NoRewardsAvailable();
        }
        require(!isPoolClosed, "Too late! Pool has been closed!");

        uint amount = rewards[msg.sender];
        rewards[msg.sender] = 0;

        Distributor rewardPool = Distributor(rewardPoolAddress);
        require(rewardPool.transfer(msg.sender, amount), "Claim Reward Failed");

        emit RewardsClaimed(msg.sender, amount);
    }

    /// @dev This function allows the owner to close the pool, and withdraw all the pool rewards
    function closePool() external whenPaused onlyOwner nonReentrant {
        require(!isPoolClosed, "Pool Already Closed");
        /**
         * This function is currently callable by only the admin. However, there are plans in motion
         * to ensure that prior to this decision being taken a vote is carried out on the Monion DAO.
         * Should the outcome of the vote indicate a need to call this function, the function will be
         * called.
         * The instance in which the function may be need is a situation where rewards have been left
         * in the pool and unclaimed by users after a significantly long time since the contract has
         * closed staking. In this instance a vote will be taken whether to withdraw the funds or burn
         * the funds.
         */
        Distributor rewardPool = Distributor(rewardPoolAddress);
        uint amount = rewardPool.poolBalance();
        isPoolClosed = true;
        require(rewardPool.transfer(owner, amount), "Close Pool Failed");

        emit ClosedPool(msg.sender, amount);
    }

    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }

    function _calcReward() public view returns (uint256) {
        uint prevBalance = balanceOf[msg.sender];
        uint diff = _lastTimeRewardApplicable() -
            userLastUpdateTime[msg.sender];
        uint numerator = prevBalance * TOTAL_REWARD * diff;
        uint denominator = MAXIMUM_POOL_MONIONS * VALIDITY_PERIOD;
        return numerator / denominator;
    }

    /// @dev returns variables used to calculated earned rewards in realtime.
    function getCalcRewardVariables()
        public
        view
        returns (
            uint256 previousBalance,
            uint lastTimeRewardApplicable,
            uint lastUpdatedTime
        )
    {
        previousBalance = balanceOf[msg.sender];
        lastTimeRewardApplicable = _lastTimeRewardApplicable();
        lastUpdatedTime = userLastUpdateTime[msg.sender];
    }

    function _lastTimeRewardApplicable() internal view returns (uint) {
        return _min(finishAt, block.timestamp);
    }

    function _poolChecker(uint amount) internal view returns (bool) {
        if ((getStakedBalance() + amount) > MAXIMUM_POOL_MONIONS) {
            int diff = int(
                (getStakedBalance() + amount) - MAXIMUM_POOL_MONIONS
            );
            revert Staking__PoolLimitReached({
                maxPoolSize: MAXIMUM_POOL_MONIONS,
                yourDeposit: amount,
                reduceBy: diff
            });
        }
        return true;
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    function getStakedBalance()
        public
        view
        returns (uint256 contractstakedBalance)
    {
        IERC20 stakingToken = IERC20(stakingTokenAddress);
        contractstakedBalance = stakingToken.balanceOf(address(this));
    }
}
