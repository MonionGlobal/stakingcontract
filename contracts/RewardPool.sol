// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "./Monion.sol";
import "./Admin.sol";

/// @dev This contract is a pool contract, it holds ERC20 tokens.
/// @author Toba Ajiboye
/// @notice This contract dispenses reward tokens for the staking contract.
contract Distributor {
    
    Monion monion;
    Admin admin;
    

    /// @param _monionAddress This is the address for the ERC20 token to be held in the pool.
    /// @param _admin This is the address for the Admin contract.
    constructor(address _monionAddress, address _admin) {
        admin = Admin(_admin);
        monion = Monion(_monionAddress);
    }

    /// @notice This function is only callable from the staking contract. 
    /// @param to This is the address we are sending the funds to. 
    /// @param amount This is the amount being sent.
    function transfer(address to, uint256 amount) public  {
        //confirm address
        //confirm reward balance
        require(msg.sender == admin.isStakingAddress(), "You cannot call this function");
        monion.transfer(to, amount);
    }

    /// @notice This function calls the balance left in the pool. 
    /// @return This function returns the balance of the ERC20 tokens in the contract.
    function poolBalance() public view returns(uint256) {
        return monion.balanceOf(address(this));
    }

}
