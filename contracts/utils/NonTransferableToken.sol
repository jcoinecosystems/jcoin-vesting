// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title NonTransferableToken
 * @dev @dev Abstract contract. Implementation of the {IERC20} and {IERC20Metadata} interfaces to display non-transferable tokens.
 */
abstract contract NonTransferableToken is IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;

    /// @dev Event emitted when the token metadata is updated.
    event NonTransferableTokenMetadataUpdated(string name, string symbol);

    /// @dev Indicates that a function can't be used.
    error NonTransferableTokenUnusedFunction();

    /**
     * @dev Sets the values for {name} and {symbol}.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     */
    constructor(string memory name_, string memory symbol_) {
        _setNonTransferableTokenNameSymbol(name_, symbol_);
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20Metadata-name}.
     * @return The name of the token.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20Metadata-symbol}.
     * @return The symbol of the token.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20Metadata-decimals}.
     * @return The number of decimals used to get its user representation.
     */
    function decimals() public view virtual returns (uint8) {
        return 18; // Placeholder, should be overridden in derived contracts.
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20-totalSupply}.
     * @return The total supply of the token.
     */
    function totalSupply() public view virtual returns (uint256) {
        return 0; // Placeholder, should be overridden in derived contracts.
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20-balanceOf}.
     * @return The balance of the specified user.
     */
    function balanceOf(address) public view virtual returns (uint256) {
        return 0; // Placeholder, should be overridden in derived contracts.
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20-transfer}.
     * @return Always reverts with NonTransferableTokenUnusedFunction.
     */
    function transfer(address, uint256) external pure returns (bool) {
        revert NonTransferableTokenUnusedFunction();
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20-allowance}.
     * @return Always return 0.
     */
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20-approve}.
     * @return Always reverts with NonTransferableTokenUnusedFunction.
     */
    function approve(address, uint256) external pure returns (bool) {
        revert NonTransferableTokenUnusedFunction();
    }

    /**
     * @dev Imitation of ERC20 function. See {IERC20-transferFrom}.
     * @return Always reverts with NonTransferableTokenUnusedFunction.
     */
    function transferFrom(
        address,
        address,
        uint256
    ) external pure returns (bool) {
        revert NonTransferableTokenUnusedFunction();
    }

    /**
     * @dev Private function to emit Transfer event.
     * @param from The address of the sender.
     * @param to The address of the recipient.
     * @param amount The amount of tokens being transferred.
     */
    function _updateNonTransferableToken(
        address from,
        address to,
        uint256 amount
    ) private {
        emit Transfer(from, to, amount);
    }

    /**
     * @dev Internal function to simulate the minting of new tokens. Emits a Transfer event.
     * @param user The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function _mintNonTransferableToken(address user, uint256 amount) internal {
        _updateNonTransferableToken(address(0), user, amount);
    }

    /**
     * @dev Internal function to simulate the burning of tokens. Emits a Transfer event.
     * @param user The address whose tokens are being burned.
     * @param amount The amount of tokens to burn.
     */
    function _burnNonTransferableToken(address user, uint256 amount) internal {
        _updateNonTransferableToken(user, address(0), amount);
    }

    /**
     * @dev Allows to change the token metadata.
     * Emits a NonTransferableTokenMetadataUpdated event.
     * @param name_ The new name of the token.
     * @param symbol_ The new symbol of the token.
     */
    function _setNonTransferableTokenNameSymbol(
        string memory name_,
        string memory symbol_
    ) internal {
        _name = name_;
        _symbol = symbol_;
        emit NonTransferableTokenMetadataUpdated(name_, symbol_);
    }
}
