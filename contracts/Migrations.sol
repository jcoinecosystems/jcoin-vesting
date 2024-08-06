// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Migrations
 * @dev This contract is used by Truffle to manage the state of migrations.
 * It keeps track of the last completed migration and ensures that migrations are only run once.
 */
contract Migrations {
    /// @notice The address of the contract owner.
    address public owner;

    /// @notice The last completed migration number.
    uint256 public last_completed_migration;

    /**
     * @dev Ensures that only the owner of the contract can call the function.
     * This modifier checks if msg.sender is the owner.
     */
    modifier restricted() {
        if (msg.sender == owner) _;
    }

    /// @dev Sets the owner of the contract to the address that deploys the contract.
    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Updates the last completed migration number.
     * @param completed The new completed migration number.
     */
    function setCompleted(uint completed) public restricted {
        last_completed_migration = completed;
    }

    /**
     * @notice Upgrades the contract to a new address.
     * @param new_address The address of the new Migrations contract.
     */
    function upgrade(address new_address) public restricted {
        Migrations upgraded = Migrations(new_address);
        upgraded.setCompleted(last_completed_migration);
    }
}
