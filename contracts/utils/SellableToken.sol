// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title SellableToken
 * @dev Abstract contract to manage a sellable token address and its decimals. Allows setting and freezing the sellable token.
 * Inherits from Ownable2Step.
 */
abstract contract SellableToken is Ownable2Step {
    /// @dev Indicates whether the sellable token is frozen.
    bool private _sellableTokenFrozen;

    /// @dev Address of the sellable token.
    address private _sellableToken;

    /// @dev Number of decimals of the sellable token.
    uint8 private _sellableTokenDecimals;

    /// @dev Event emitted when the sellable token is updated.
    event SellableTokenUpdated(address token, uint8 decimals);

    /// @dev Event emitted when the sellable token is frozen.
    event SellableTokenFrozen();

    /// @dev Error thrown when the sellable token address is zero.
    error SellableTokenIsZero();

    /// @dev Error thrown when the sellable token decimals is zero.
    error SellableTokenDecimalsIsZero();

    /// @dev Error thrown when the sellable token is frozen.
    error SellableTokenIsFrozen();

    /**
     * @dev Sets the initial values for the sellable token and its decimals.
     * @param token The address of the sellable token.
     * @param decimals The number of decimals of the sellable token. Must be greater than 0.
     */
    constructor(address token, uint8 decimals) {
        _setSellableToken(token, decimals);
    }

    /// @dev Modifier to check if the sellable token address is not zero.
    modifier whenSellableTokenIsNotZero() {
        if (_getSellableToken() == address(0)) {
            revert SellableTokenIsZero();
        }
        _;
    }

    /**
     * @notice Gets the sellable token details.
     * @return isFrozen Boolean indicating if the sellable token is frozen.
     * @return token The address of the sellable token.
     * @return decimals The number of decimals of the sellable token.
     */
    function getSellableToken()
        external
        view
        returns (bool isFrozen, address token, uint8 decimals)
    {
        isFrozen = _isSellableTokenFrozen();
        token = _getSellableToken();
        decimals = _getSellableTokenDecimals();
    }

    /**
     * @notice Sets the sellable token and its decimals.
     * @dev Can only be called by the contract owner and if the sellable token is not frozen.
     * @param token The address of the sellable token.
     * @param decimals The number of decimals of the sellable token. Must be greater than 0.
     */
    function setSellableToken(
        address token,
        uint8 decimals
    ) external onlyOwner {
        if (_isSellableTokenFrozen()) {
            revert SellableTokenIsFrozen();
        }
        _setSellableToken(token, decimals);
    }

    /**
     * @notice Freezes the sellable token, preventing further changes to its address or decimals.
     * @dev Can only be called by the contract owner and only if the sellable token is not already frozen.
     * This action is irreversible. Once the sellable token is frozen, it cannot be unfrozen.
     * Emits a SellableTokenFrozen event upon successful freezing of the sellable token.
     */
    function freezeSellableToken()
        external
        whenSellableTokenIsNotZero
        onlyOwner
    {
        if (_sellableTokenFrozen) {
            revert SellableTokenIsFrozen();
        }

        _sellableTokenFrozen = true;
        emit SellableTokenFrozen();
    }

    /**
     * @dev Internal function to get the address of the sellable token.
     * @return The address of the sellable token.
     */
    function _getSellableToken() internal view returns (address) {
        return _sellableToken;
    }

    /**
     * @dev Internal function to get the number of decimals of the sellable token.
     * @return The number of decimals of the sellable token.
     */
    function _getSellableTokenDecimals() internal view returns (uint8) {
        return _sellableTokenDecimals;
    }

    /**
     * @dev Private function to check if the sellable token is frozen.
     * @return Boolean indicating if the sellable token is frozen.
     */
    function _isSellableTokenFrozen() private view returns (bool) {
        return _sellableTokenFrozen;
    }

    /**
     * @dev Private function to set the sellable token and its decimals.
     * Emits a SellableTokenUpdated event.
     * @param token The address of the sellable token.
     * @param decimals The number of decimals of the sellable token. Must be greater than 0.
     */
    function _setSellableToken(address token, uint8 decimals) private {
        if (decimals == 0) {
            revert SellableTokenDecimalsIsZero();
        }

        _sellableToken = token;
        _sellableTokenDecimals = decimals;
        emit SellableTokenUpdated(token, decimals);
    }
}
