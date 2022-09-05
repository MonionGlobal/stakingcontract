// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.7;

contract Admin {
    
    address public owner; //Owner of the contract
    address staking; //Address of staking contract
    constructor() {
        owner = msg.sender;
    }

    /// @dev This function MUST be set once the staking contract is deployed.
    /// @notice This function can only be called by the owner.
    /// @param _account This is the address for the staking contract.
    function setStakingAddress(address _account) external {
        require(msg.sender == owner, "You cannot call this function");
        require(_account != address(0), "Cannot add zero address");
        staking = _account;
    }

    /// @dev This function allows a user to return the address of the staking contract deployed.
    /// @return This function returns the stakingAddress of the contract.
    function isStakingAddress() public view returns(address) {
        return staking;
    }

}
