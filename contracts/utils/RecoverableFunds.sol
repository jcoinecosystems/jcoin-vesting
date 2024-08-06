// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RecoverableFunds
 * @dev Abstract contract that allows the owner to recover accidentally sent ERC20 tokens
 * and native coins (ETH) that are not part of the project's tracked funds.
 * Ensures the amount to be recovered does not exceed the recoverable balance.
 * Inherits from Ownable2Step and ReentrancyGuard.
 */
abstract contract RecoverableFunds is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /**
     * @dev Emitted when funds are recovered.
     * @param user The address that received the recovered funds.
     * @param token The address of the recovered ERC20 token or address(0) for ETH.
     * @param amount The amount of ERC20 tokens or ETH recovered.
     */
    event FundsRecovered(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    /// @dev Error to indicate that the amount to be recovered exceeds the recoverable balance.
    error AmountExceedsRecoverableFunds();

    /// @dev Error to indicate that the recipient address is zero.
    error RecipientIsZeroAddress();

    /**
     * @notice Returns the recoverable amount of a specific token or ETH.
     * @dev If the `token` is the zero address, it returns the balance of the contract in ETH.
     * Otherwise, it returns the balance of the specified ERC20 token held by the contract.
     * This function is designed to be overridden in derived contracts if needed.
     * @param token The address of the ERC20 token or the zero address for ETH.
     * @return The recoverable amount of the specified token or ETH.
     */
    function getRecoverableFunds(
        address token
    ) public view virtual returns (uint256) {
        if (token == address(0)) return address(this).balance;
        else return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Allows the owner to recover ERC20 tokens and native coins (ETH) accidentally sent to the contract.
     * @dev Can only be called by the contract owner.
     * Ensures the amount to be recovered does not exceed the recoverable balance.
     * Emits a FundsRecovered event.
     * @param user The address to receive recovered funds from the contract.
     * @param token The address of the ERC20 token to recover or address(0) to recover ETH.
     * @param amount The amount of ERC20 tokens or ETH to recover.
     * @return Returns true if the recovery was successful.
     */
    function recoverFunds(
        address user,
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant returns (bool) {
        if (user == address(0)) {
            revert RecipientIsZeroAddress();
        }

        uint256 recoverableAmount = getRecoverableFunds(token);
        if (amount > recoverableAmount) {
            revert AmountExceedsRecoverableFunds();
        }

        _transferRecoverableFundsTo(user, token, amount);
        emit FundsRecovered(user, token, amount);
        return true;
    }

    /**
     * @dev Private function to handle the transfer of recovered funds.
     * @param user The address to receive the recovered funds.
     * @param token The address of the ERC20 token to recover or address(0) to recover ETH.
     * @param amount The amount of ERC20 tokens or ETH to recover.
     */
    function _transferRecoverableFundsTo(
        address user,
        address token,
        uint256 amount
    ) private {
        if (token == address(0)) {
            payable(user).sendValue(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
    }
}
