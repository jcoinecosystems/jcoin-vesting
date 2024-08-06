// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

interface ITokenVesting {
    /**
     * @notice Handles the purchase of tokens for a specific user during a token sale stage.
     * @dev This function is called by the TokenSale contract when tokens are purchased.
     * It verifies the allocation exists and increases the vested amount for the user.
     * @param user The address of the user purchasing tokens.
     * @param stageId The ID of the sale stage.
     * @param tokensToBuy The amount of tokens being purchased.
     * @return bool Returns true if the purchase is successfully processed.
     */
    function onTokensPurchase(
        address user,
        uint256 stageId,
        uint256 tokensToBuy
    ) external returns (bool);
}
