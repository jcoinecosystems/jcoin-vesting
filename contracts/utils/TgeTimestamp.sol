// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title TgeTimestamp
 * @dev Abstract contract to manage the Token Generation Event (TGE) timestamp.
 * Allows setting, freezing, and checking the TGE timestamp.
 * Inherits from Ownable2Step.
 */
abstract contract TgeTimestamp is Ownable2Step {
    /// @dev Timestamp of the Token Generation Event (TGE).
    uint256 private _tgeTimestamp;

    /// @dev Flag to indicate if the TGE timestamp is frozen.
    bool private _tgeTimestampFrozen;

    /// @dev Event emitted when the TGE timestamp is changed.
    event TgeTimestampUpdated(uint256 tgeTimestamp);

    /// @dev Event emitted when the TGE timestamp is frozen.
    event TgeTimestampFrozen();

    /// @dev Error indicating that the TGE has not yet passed.
    error TgeTimestampNotPassed();

    /// @dev Error indicating that the TGE has already passed.
    error TgeTimestampPassed();

    /// @dev Error indicating that the TGE timestamp is zero.
    error TgeTimestampIsZero();

    /// @dev Error indicating that the TGE timestamp is frozen and cannot be changed.
    error TgeTimestampIsFrozen();

    /// @dev Error indicating that the provided timestamp has already passed.
    error TimeAlreadyPassed();

    /**
     * @dev Sets the initial value for the TGE timestamp.
     * @param tgeTimestamp The initial TGE timestamp.
     */
    constructor(uint256 tgeTimestamp) {
        _setTgeTimestamp(tgeTimestamp);
    }

    /// @dev Modifier to make a function callable only when the TGE has passed.
    modifier whenTgePassed() {
        if (!_isTgePassed()) {
            revert TgeTimestampNotPassed();
        }
        _;
    }

    /**
     * @notice Returns the TGE timestamp details.
     * @return isFrozen Boolean indicating if the TGE timestamp is frozen.
     * @return tge The TGE timestamp.
     */
    function getTge() external view returns (bool isFrozen, uint256 tge) {
        isFrozen = _isTgeTimestampFrozen();
        tge = _getTgeTimestamp();
    }

    /**
     * @notice Sets the TGE timestamp.
     * @dev Can only be called by the contract owner and if the TGE timestamp is not frozen and has not passed.
     * @param newTgeTimestamp The new TGE timestamp.
     */
    function setTgeTimestamp(uint256 newTgeTimestamp) external onlyOwner {
        uint256 currentTge = _getTgeTimestamp();
        if (currentTge > 0 && block.timestamp >= currentTge) {
            revert TgeTimestampPassed();
        }

        if (block.timestamp > newTgeTimestamp) {
            revert TimeAlreadyPassed();
        }

        if (_isTgeTimestampFrozen()) {
            revert TgeTimestampIsFrozen();
        }

        _setTgeTimestamp(newTgeTimestamp);
    }

    /**
     * @notice Freezes the TGE timestamp, preventing any future changes.
     * @dev Can only be called by the contract owner and if the TGE timestamp is not frozen and is not zero.
     */
    function freezeTgeTimestamp() external onlyOwner {
        if (_getTgeTimestamp() == 0) {
            revert TgeTimestampIsZero();
        }
        if (_tgeTimestampFrozen) {
            revert TgeTimestampIsFrozen();
        }

        _tgeTimestampFrozen = true;
        emit TgeTimestampFrozen();
    }

    /**
     * @dev Internal function to get the TGE timestamp.
     * @return uint256 The TGE timestamp.
     */
    function _getTgeTimestamp() internal view returns (uint256) {
        return _tgeTimestamp;
    }

    /**
     * @dev Internal function to check if the Token Generation Event (TGE) has passed.
     * @return Returns true if the TGE has passed, false otherwise.
     */
    function _isTgePassed() internal view returns (bool) {
        uint256 tge = _getTgeTimestamp();
        if (tge == 0 || block.timestamp < tge) {
            return false;
        }
        return true;
    }

    /**
     * @dev Private function to check if the TGE timestamp is frozen.
     * @return bool True if the TGE timestamp is frozen, false otherwise.
     */
    function _isTgeTimestampFrozen() private view returns (bool) {
        return _tgeTimestampFrozen;
    }

    /**
     * @dev Private function to set the TGE (Token Generation Event) timestamp
     * Emits a TgeTimestampUpdated event.
     * @param tgeTimestamp The new TGE timestamp.
     */
    function _setTgeTimestamp(uint256 tgeTimestamp) private {
        _tgeTimestamp = tgeTimestamp;
        emit TgeTimestampUpdated(tgeTimestamp);
    }
}
