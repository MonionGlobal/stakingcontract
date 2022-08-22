// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./RewardPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

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

contract StakingRewards is Pausable, ReentrancyGuard {
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

    IERC20 public immutable stakingToken;
    Distributor rewardPool; 

    address public owner; // Contract owner
    uint public constant validityPeriod = 60 * 60 * 24 * 365; //Length of days for staking: 1 year
    uint public constant maximumPoolMonions = 5000000 * 1e18; //Maximum Pool size for Staking
    uint public constant totalReward = 100000 * 1e18; //20% return on Max Pool size.

    uint public totalSupply; //Total amount of ERC20 tokens currently staked in the contract.
    uint public finishAt; //Time at which staking becomes closed. i.e. Current time + 1 year,

    bool public isPoolClosed; //Checker whether the pool will pay rewards or not.
    bool public contractHasExpired; // checker whether the contract has passed

    mapping(address => uint) public userToUnstakingTime; //Tracks unbonding time.
    mapping(address => bool) public unstakingFlagPerUser; //Tracks unstake state
    mapping(address => uint) public userLastUpdateTime; //Tracks the last time a user interacted with the contract.
    mapping(address => uint) public rewards; //Tracks user's rewards balance.
    mapping(address => uint) public balanceOf; //Tracks user's staked balance.

    /// @param _stakingToken This is the Address of the ERC20 token we are staking.
    /// @param _rewardPool This is the distributor contract that pays out rewards.
    constructor(address _stakingToken, address _rewardPool) ReentrancyGuard() {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardPool = Distributor(_rewardPool);
        finishAt = block.timestamp + validityPeriod; //Time after which staking is no longer permitted.
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
    {
        if (isPoolClosed) {
            revert Staking__PoolAlreadyClosed();
        }

        if (block.timestamp > finishAt) {
            revert Staking__PoolExceededValidityPeriod();
        }

        if (amount > stakingToken.balanceOf(msg.sender)) {
            revert Staking__StakeExceedsYourBalance();
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);

        balanceOf[msg.sender] += amount;
        totalSupply += amount;

        emit Staked(
            msg.sender,
            amount,
            balanceOf[msg.sender],
            rewards[msg.sender],
            totalSupply
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
    {
        if (balanceOf[msg.sender] - amount < 0) {
            revert Staking__WithdrawLessThanYourBalance();
        }
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;

        stakingToken.transfer(msg.sender, amount);

        emit Unstaked(
            msg.sender,
            amount,
            balanceOf[msg.sender],
            rewards[msg.sender],
            totalSupply
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
                console.log(
                    "Unstake initiated for %s, 24h countdown begins...!",
                    msg.sender
                );
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
        // if(balanceOf[msg.sender] <= 0){
        //     revert Staking__NoStakeInPool();
        // }

        if (rewards[msg.sender] <= 0) {
            revert Staking__NoRewardsAvailable();
        }
        require(!isPoolClosed, "Too late! Pool has been closed!");

        uint amount = rewards[msg.sender];
        rewards[msg.sender] = 0;
        stakingToken.transfer(msg.sender, amount);

        emit RewardsClaimed(msg.sender, amount);
    }

    /// @dev This function allows the owner to close the pool, and withdraw all the pool rewards
    function closePool() external whenPaused onlyOwner {
        require(!isPoolClosed, "Pool Already Closed");

        uint amount = rewardPool.poolBalance();
        isPoolClosed = true;
        rewardPool.transfer(owner, amount);

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
        uint numerator = prevBalance * totalReward * diff;
        uint denominator = maximumPoolMonions * validityPeriod;
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
        if ((totalSupply + amount) > maximumPoolMonions) {
            int diff = int((totalSupply + amount) - maximumPoolMonions);
            revert Staking__PoolLimitReached({
                maxPoolSize: maximumPoolMonions,
                yourDeposit: amount,
                reduceBy: diff
            });
        }
        return true;
    }

    // function _timeChecker() internal view returns(bool){

    // }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
}
