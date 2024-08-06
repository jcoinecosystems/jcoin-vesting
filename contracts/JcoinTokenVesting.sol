// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./utils/RecoverableFunds.sol";
import "./utils/SellableToken.sol";
import "./utils/TgeTimestamp.sol";
import "./utils/NonTransferableToken.sol";
import "./interfaces/ITokenVesting.sol";

/**
 * @title JcoinTokenVesting
 * @dev Abstract contract to manage token vesting schedules for multiple allocations and users.
 * Inherits from Ownable2Step, SellableToken, TgeTimestamp, NonTransferableToken and RecoverableFunds.
 */
contract JcoinTokenVesting is
    Ownable2Step,
    SellableToken,
    TgeTimestamp,
    NonTransferableToken,
    RecoverableFunds,
    ITokenVesting
{
    using SafeERC20 for IERC20;
    using Strings for uint256;

    /**
     * @dev Constant denominator for calculating percentages.
     * 10000 represents 100.00%. 1 represents 0.01%.
     */
    uint256 private constant DENOMINATOR = 10_000;

    /**
     * @dev The status of automatic supply of tokens.
     * When set to true, tokens will be automatically supplied based on certain conditions.
     * This can occur when allocating tokens or when claiming tokens.
     */
    bool private _autoSupply;

    /**
     * @dev The status of automatic supply of tokens upon claim.
     * When set to true, tokens will be automatically supplied when a claim is made.
     */
    bool private _autoSupplyOnClaim;

    /**
     * @dev The address from which tokens will be automatically supplied.
     * This address is used as the source for token transfers during automatic supply.
     */
    address private _autoSupplyFrom;

    /**
     * @dev Flag indicating whether tokens should be automatically claimed upon purchase.
     * If set to true and the Token Generation Event (TGE) has passed, tokens will be
     * immediately issued to the buyer if there is no vesting schedule.
     */
    bool private _autoClaimAfterTge;

    /// @dev List of allowed allocation IDs.
    bytes32[] private _allocationIds;

    /// @dev Mapping to check if an allocation ID exists in the allowed allocation IDs list.
    mapping(bytes32 allocationId => bool) private _allocationIdExist;

    /// @dev Total amount of tokens reserved across all allocations.
    uint256 private _totalReserved;

    /// @dev Total amount of tokens vested across all allocations.
    uint256 private _totalVested;

    /// @dev Total amount of tokens claimed by all users.
    uint256 private _totalClaimed;

    /**
     * @dev Struct to store vesting data for each allocation.
     * @param reserved The total amount of tokens reserved for this allocation.
     * @param vested Total amount of tokens vested.
     * @param claimed Total amount of tokens claimed.
     * @param lockup The lock-up period before vesting starts.
     * @param cliff The cliff period during which tokens cannot be claimed.
     * @param vesting The total vesting period over which tokens are gradually unlocked.
     * @param tgeUnlock The percentage of tokens unlocked immediately after the Token Generation Event (TGE). 1/10000 = 0.01%.
     * @param unlockDelay The delay between successive unlocks after the cliff period.
     */
    struct VestingData {
        uint256 reserved; // Total amount of tokens reserved.
        uint256 vested; // Total amount of tokens vested.
        uint256 claimed; // Total amount of tokens claimed.
        uint256 lockup; // Lock-up period for vesting.
        uint256 cliff; // Cliff period for vesting.
        uint256 vesting; // Vesting time.
        uint256 tgeUnlock; // Initial unlock percentage after TGE. 1/10000 = 0.01%.
        uint256 unlockDelay; // Delay between successive unlocks.
    }

    /**
     * @dev Struct to store vesting schedule parameters for an allocation.
     * @param allocationId The ID of the allocation.
     * @param reserved The total amount of tokens reserved for this allocation.
     * @param lockup The lock-up period before vesting starts.
     * @param cliff The cliff period during which tokens cannot be claimed.
     * @param vesting The total vesting period over which tokens are gradually unlocked.
     * @param tgeUnlock The percentage of tokens unlocked immediately after the Token Generation Event (TGE).
     * @param unlockDelay The delay between successive unlocks after the cliff period.
     */
    struct VestingSchedule {
        bytes32 allocationId;
        uint256 reserved;
        uint256 lockup;
        uint256 cliff;
        uint256 vesting;
        uint256 tgeUnlock;
        uint256 unlockDelay;
    }

    /// @dev Mapping to store vesting data for each allocation by its ID.
    mapping(bytes32 allocationId => VestingData) private _vesting;

    /**
     * @dev Struct to store vesting data for each user.
     * @param vested The amount of tokens vested in that allocation.
     * @param claimed The amount of tokens claimed by the user in that allocation.
     */
    struct UserVestingData {
        uint256 vested; // User vested tokens at each allocation.
        uint256 claimed; // User claimed tokens at each allocation.
    }

    /// @dev Mapping to store vesting data for each user by their address.
    mapping(address user => mapping(bytes32 allocationId => UserVestingData))
        private _userVesting;

    /// @dev Address of the TokenSale contract.
    address private _tokenSale;

    /// @dev Flag indicating if the TokenSale address is frozen.
    bool private _tokenSaleFrozen;

    /**
     * @dev Emitted when the auto supply settings are updated.
     * @param autoSupply The new status of the auto supply.
     * @param autoSupplyOnClaim The new status of the auto supply upon claim.
     * @param autoSupplyFrom The new address from which the tokens will be supplied.
     */
    event AutoSupplyUpdated(
        bool autoSupply,
        bool autoSupplyOnClaim,
        address autoSupplyFrom
    );

    /**
     * @dev Emitted when the auto-claim status is updated.
     * @param status The new status of auto-claim.
     */
    event AutoClaimAfterTgeUpdated(bool status);

    /**
     * @dev Emitted when a vesting allocation is updated.
     * @param allocationId The ID of the allocation that was updated.
     * @param reserved The updated total amount of tokens reserved for this allocation.
     * @param lockup The updated lock-up period before vesting starts, in seconds.
     * @param cliff The updated cliff period during which tokens cannot be claimed, in seconds.
     * @param vesting The updated total vesting period over which tokens are gradually unlocked, in seconds.
     * @param tgeUnlock The updated percentage of tokens unlocked immediately after the Token Generation Event (TGE), expressed in basis points (1/10000 = 0.01%).
     * @param unlockDelay The updated delay between successive unlocks after the cliff period, in seconds.
     */
    event AllocationUpdated(
        bytes32 indexed allocationId,
        uint256 reserved,
        uint256 lockup,
        uint256 cliff,
        uint256 vesting,
        uint256 tgeUnlock,
        uint256 unlockDelay
    );

    /**
     * @dev Emitted when a vesting allocation is deleted.
     * @param allocationId The ID of the allocation that was deleted.
     */
    event AllocationDeleted(bytes32 indexed allocationId);

    /**
     * @dev Emitted when tokens are supplied to the contract for vesting.
     * @param amount The amount of tokens that were supplied.
     */
    event TokensSupplied(uint256 amount);

    /**
     * @dev Emitted when tokens are vested for a user at a specific allocation.
     * @param user The address of the user whose tokens are vested.
     * @param allocationId The ID of the allocation in which tokens are vested.
     * @param amount The amount of tokens vested.
     */
    event VestingAccrued(
        address indexed user,
        bytes32 indexed allocationId,
        uint256 amount
    );

    /**
     * @dev Emitted when a user claims vested tokens.
     * @param user The address of the user who claims the tokens.
     * @param allocationId The ID of the allocation from which tokens are claimed.
     * @param amount The amount of tokens claimed.
     */
    event VestingClaimed(
        address indexed user,
        bytes32 indexed allocationId,
        uint256 amount
    );

    /**
     * @dev Emitted when the TokenSale address is changed.
     * @param tokenSale The new TokenSale address.
     */
    event TokenSaleUpdated(address tokenSale);

    /// @dev Emitted when the TokenSale is frozen.
    event TokenSaleFrozen();

    /// @dev Error thrown when an allocation is not exist.
    error AllocationNotFound(bytes32 allocationId);

    /**
     * @dev Error that is thrown when the new reserved amount is less than the already vested amount for a given allocation.
     * @param allocationId The ID of the allocation that has this issue.
     */
    error ReservedLessThanVested(bytes32 allocationId);

    /**
     * @dev Error that is thrown when the vested amount exceeds the reserved amount for a given allocation.
     * @param allocationId The ID of the allocation that exceeded its reserved amount.
     */
    error AllocationExceeded(bytes32 allocationId);

    /// @dev Error indicating that the allocation has already been used.
    error AllocationAlreadyUsed();

    /// @dev Error indicating that the TGE unlock percentage exceeds the maximum allowed value.
    error TgeUnlockExceedsMaximum();

    /// @dev Error thrown when the TokenSale address is zero.
    error TokenSaleIsZero();

    /// @dev Error thrown when the TokenSale is frozen and an update is attempted.
    error TokenSaleIsFrozen();

    /// @dev Error to be thrown when an unauthorized account tries to call a restricted function.
    error UnauthorizedAccount();

    /// @dev Error indicating that there is a mismatch between the provided parameters.
    error ParametersMismatch();

    /// @dev Error indicating an invalid token amount.
    error InvalidTokenAmount();

    /**
     * @dev Constructor for the JcoinTokenVesting contract.
     * @param sellableToken The address of the token that will be sold.
     * @param sellableTokenDecimals The number of decimals of the sellable token.
     * @param vestedTokenName The name of the vested token.
     * @param vestedTokenSymbol The symbol of the vested token.
     */
    constructor(
        address sellableToken,
        uint8 sellableTokenDecimals,
        string memory vestedTokenName,
        string memory vestedTokenSymbol
    )
        Ownable(_msgSender())
        TgeTimestamp(0)
        SellableToken(sellableToken, sellableTokenDecimals)
        NonTransferableToken(vestedTokenName, vestedTokenSymbol)
    {
        _setAutoClaimAfterTge(false);
    }

    /**
     * @dev Modifier to check if the allocation ID exists.
     * Reverts if the allocation does not exist.
     * @param allocationId The ID of the allocation to check.
     */
    modifier allocationIdExists(bytes32 allocationId) {
        _checkAllocationIdExistence(allocationId);
        _;
    }

    /// @dev Modifier to restrict access to only the TokenSale contract.
    modifier onlyTokenSale() {
        if (_tokenSale == address(0)) {
            revert TokenSaleIsZero();
        }
        if (_tokenSale != _msgSender()) {
            revert UnauthorizedAccount();
        }
        _;
    }

    /**
     * @notice Returns the total supply of tokens that users have not yet received from vesting.
     * @dev This function overrides the ERC20 totalSupply function to reflect the total amount of vested tokens
     * that are still locked and have not been claimed by users.
     * @return The total amount of unclaimed vested tokens.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalVested - _totalClaimed;
    }

    /**
     * @notice Returns the balance of tokens that a user has not yet received from vesting.
     * @dev This function overrides the ERC20 balanceOf function to reflect the amount of vested tokens
     * that are still locked and have not been claimed by the user.
     * @param user The address of the user.
     * @return The amount of unclaimed vested tokens for the user.
     */
    function balanceOf(address user) public view override returns (uint256) {
        uint256 vested;
        uint256 claimed;

        bytes32[] memory allocationIds = _getAllocationIds();
        uint256 totalAllocations = allocationIds.length;
        for (uint256 i = 0; i < totalAllocations; i++) {
            bytes32 allocationId = allocationIds[i];
            UserVestingData memory vestingData = _getUserVesting(
                user,
                allocationId
            );
            vested += vestingData.vested;
            claimed += vestingData.claimed;
        }
        return vested - claimed;
    }

    /**
     * @notice Returns the number of decimals used to get the user representation of vested tokens.
     * @dev This function overrides the ERC20 decimals function to return the number of decimals
     * of the vested token, which is the same as the sellable token's decimals.
     * @return The number of decimals of the vested token.
     */
    function decimals() public view virtual override returns (uint8) {
        return _getSellableTokenDecimals();
    }

    /**
     * @notice Returns the recoverable funds for a specific token.
     * @dev Overrides the getRecoverableFunds function from RecoverableFunds contract.
     * If the token is a payment token, it calculates the balance excluding deposits and unclaimed raised funds.
     * If the token is the sellable token, it calculates the balance excluding the total unclaimed amount.
     * @param token The address of the token.
     * @return The amount of recoverable funds.
     */
    function getRecoverableFunds(
        address token
    ) public view override returns (uint256) {
        address sellableToken = _getSellableToken();
        if (token == sellableToken) {
            uint256 accountedFunds = _totalVested - _totalClaimed;
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (accountedFunds > balance) {
                return 0;
            }
            return balance - accountedFunds;
        } else {
            return super.getRecoverableFunds(token);
        }
    }

    /**
     * @notice Returns the current auto supply status and the address from which tokens are supplied.
     * @dev This function can be called externally to get the current status and address for automatic token supply.
     * @return autoSupply The current status of the auto supply (if autoSupplyOnClaim is false, then for allocating; if autoSupplyOnClaim is true, then for claiming).
     * @return autoSupplyOnClaim The current status of the auto supply upon claim (true if enabled, false if disabled).
     * @return autoSupplyFrom The address from which the tokens will be supplied.
     */
    function getAutoSupply()
        external
        view
        returns (
            bool autoSupply,
            bool autoSupplyOnClaim,
            address autoSupplyFrom
        )
    {
        autoSupply = _autoSupply;
        autoSupplyOnClaim = _autoSupplyOnClaim;
        autoSupplyFrom = _autoSupplyFrom;
    }

    /**
     * @notice Returns the allocation ID for a given allocation name.
     * @dev This function computes the keccak-256 hash of the given allocation name, subtracts 1, and returns it as bytes32.
     * @param allocationName The name of the allocation.
     * @return The ID of the allocation.
     */
    function computeAllocationId(
        string memory allocationName
    ) external pure returns (bytes32) {
        return _computeAllocationId(allocationName);
    }

    /**
     * @notice Verifies if a specified allocation ID exists in the allowed allocation IDs list.
     * @param allocationId The ID of the allocation to verify.
     * @return bool True if the allocation exists, false otherwise.
     */
    function isAllocationIdExist(
        bytes32 allocationId
    ) external view returns (bool) {
        return _isAllocationIdExist(allocationId);
    }

    /**
     * @notice Retrieves the list of all allowed allocation IDs.
     * @return bytes32[] List of allowed allocation IDs.
     */
    function getAllocationIds() external view returns (bytes32[] memory) {
        return _getAllocationIds();
    }

    /**
     * @notice Returns the vesting parameters for a specific allocation.
     * @dev This function retrieves the vesting details such as lockup period, cliff period, total vesting duration,
     * TGE unlock percentage, and unlock delay for the specified allocation.
     * @param allocationId The ID of the vesting allocation to retrieve.
     * @return reserved The total amount of tokens reserved for this allocation.
     * @return vested Total amount of tokens vested.
     * @return claimed Total amount of tokens claimed.
     * @return lockup The lock-up period before vesting starts.
     * @return cliff The cliff period during which tokens cannot be claimed.
     * @return vesting The total vesting period over which tokens are gradually unlocked.
     * @return tgeUnlock The percentage of tokens unlocked immediately after the Token Generation Event (TGE).
     * @return unlockDelay The delay between successive unlocks after the cliff period.
     */
    function getVesting(
        bytes32 allocationId
    )
        external
        view
        returns (
            uint256 reserved,
            uint256 vested,
            uint256 claimed,
            uint256 lockup,
            uint256 cliff,
            uint256 vesting,
            uint256 tgeUnlock,
            uint256 unlockDelay
        )
    {
        VestingData memory vestingData = _getVesting(allocationId);

        reserved = vestingData.reserved;
        vested = vestingData.vested;
        claimed = vestingData.claimed;
        lockup = vestingData.lockup;
        cliff = vestingData.cliff;
        vesting = vestingData.vesting;
        tgeUnlock = vestingData.tgeUnlock;
        unlockDelay = vestingData.unlockDelay;
    }

    /**
     * @notice Returns the vesting data for all allocations.
     * @return allocationIds An array of allocation IDs.
     * @return vestings An array of vesting data for all allocations.
     */
    function getVestings()
        external
        view
        returns (bytes32[] memory allocationIds, VestingData[] memory vestings)
    {
        allocationIds = _getAllocationIds();
        uint256 totalAllocations = allocationIds.length;
        vestings = new VestingData[](totalAllocations);
        for (uint256 i = 0; i < totalAllocations; i++) {
            bytes32 allocationId = allocationIds[i];
            vestings[i] = _getVesting(allocationId);
        }
    }

    /**
     * @notice Returns the overall state of vesting at a given time.
     * @param atTime The timestamp at which to check the state.
     * @return tge The TGE (Token Generation Event) timestamp.
     * @return autoClaimAfterTge The status of the auto-claim feature.
     * @return tokenSale The address of the TokenSale contract.
     * @return tokenSaleFrozen The status indicating if the TokenSale address is frozen.
     * @return totalReserved The total number of tokens reserved across all allocations.
     * @return totalVested The total number of tokens vested.
     * @return totalClaimed The total number of tokens claimed.
     * @return totalUnlocked The total number of tokens unlocked.
     * @return reserved An array of reserved tokens for each allocation.
     * @return vested An array of vested tokens for each allocation.
     * @return claimed An array of claimed tokens for each allocation.
     * @return unlocked An array of unlocked tokens for each allocation.
     * @return allocationIds An array of allocation IDs.
     */
    function getState(
        uint256 atTime
    )
        external
        view
        returns (
            uint256 tge,
            bool autoClaimAfterTge,
            address tokenSale,
            bool tokenSaleFrozen,
            uint256 totalReserved,
            uint256 totalVested,
            uint256 totalClaimed,
            uint256 totalUnlocked,
            uint256[] memory reserved,
            uint256[] memory vested,
            uint256[] memory claimed,
            uint256[] memory unlocked,
            bytes32[] memory allocationIds
        )
    {
        if (atTime == 0) {
            atTime = block.timestamp;
        }

        tge = _getTgeTimestamp();
        autoClaimAfterTge = _autoClaimAfterTge;
        tokenSale = _tokenSale;
        tokenSaleFrozen = _tokenSaleFrozen;

        totalReserved = _totalReserved;

        allocationIds = _getAllocationIds();
        (
            totalVested,
            totalClaimed,
            totalUnlocked,
            reserved,
            vested,
            claimed,
            unlocked
        ) = _calculateVestingStateAtTime(allocationIds, atTime);
    }

    /**
     * @notice Returns the vesting data for a specific user.
     * @dev This function retrieves the vesting details such as the total vested tokens, claimed tokens, unlocked tokens,
     * and allocation details for the specified user at a given time.
     * @param user The address of the user.
     * @param atTime The timestamp at which to check the user's vesting state.
     * @return totalVested The amount of vested tokens.
     * @return totalClaimed The amount of claimed tokens.
     * @return totalUnlocked The total number of tokens unlocked.
     * @return vested An array of vested tokens for each allocation.
     * @return claimed An array of claimed tokens for each allocation.
     * @return unlocked An array of unlocked tokens for each allocation.
     * @return allocationIds An array of allocation IDs.
     */
    function getUserState(
        address user,
        uint256 atTime
    )
        external
        view
        returns (
            uint256 totalVested,
            uint256 totalClaimed,
            uint256 totalUnlocked,
            uint256[] memory vested,
            uint256[] memory claimed,
            uint256[] memory unlocked,
            bytes32[] memory allocationIds
        )
    {
        if (atTime == 0) {
            atTime = block.timestamp;
        }

        allocationIds = _getAllocationIds();
        (
            totalVested,
            totalClaimed,
            totalUnlocked,
            vested,
            claimed,
            unlocked
        ) = _calculateUserVestingStateAtTime(allocationIds, user, atTime);
    }

    /**
     * @notice Shows the amount of tokens required to be supplied for vesting.
     * @dev This function can be called externally to get the current required supply of tokens for vesting.
     * It calculates the total supply of tokens required for vesting by subtracting the total claimed tokens from the total vested tokens,
     * and adjusting it based on the current token balance of the contract.
     * @return uint256 The amount of tokens required for vesting.
     */
    function getRequiredTokensSupply() external view returns (uint256) {
        return _calculateRequiredTokensSupply();
    }

    /**
     * @notice Allows the caller to claim their vested tokens.
     * @dev This function can only be called if the TGE (Token Generation Event) has passed.
     */
    function claim() external whenTgePassed {
        _claim(_msgSender());
    }

    /**
     * @notice Allows the owner to force claim vested tokens for multiple users.
     * @dev This function can only be called if the TGE (Token Generation Event) has passed.
     * Can only be called by the contract owner.
     * @param users An array of addresses for which to force claim vested tokens.
     */
    function claimForced(
        address[] memory users
    ) external whenTgePassed onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            _claim(users[i]);
        }
    }

    /**
     * @notice Sets the vesting parameters for a specific allocation.
     * @dev Can only be called by the contract owner.
     * WARNING: This function is not synchronized with the sales stages.
     * Ensures that the vesting parameters are set in accordance with the sales strategy.
     * Ensures that the TGE unlock percentage does not exceed the maximum allowed value.
     * @param allocationId The ID of the allocation to set the vesting parameters.
     * @param reserved The total amount of tokens reserved for this allocation.
     * @param lockup The lock-up period before vesting starts.
     * @param cliff The cliff period during which tokens cannot be claimed.
     * @param vesting The total vesting period over which tokens are gradually unlocked.
     * @param tgeUnlock The percentage of tokens unlocked immediately after the Token Generation Event (TGE).
     * @param unlockDelay The delay between successive unlocks after the cliff period.
     */
    function setVestingSchedule(
        bytes32 allocationId,
        uint256 reserved,
        uint256 lockup,
        uint256 cliff,
        uint256 vesting,
        uint256 tgeUnlock,
        uint256 unlockDelay
    ) external onlyOwner {
        _setVestingSchedule(
            allocationId,
            reserved,
            lockup,
            cliff,
            vesting,
            tgeUnlock,
            unlockDelay
        );
    }

    /**
     * @notice Sets the vesting parameters for multiple allocations at once.
     * @dev Can only be called by the contract owner.
     * WARNING: This function is not synchronized with the sales stages.
     * Ensures that the vesting parameters are set in accordance with the sales strategy.
     * Ensures that the TGE unlock percentage does not exceed the maximum allowed value.
     * @param schedules An array of VestingSchedule structs containing the vesting parameters for each allocation.
     */
    function setVestingScheduleBatch(
        VestingSchedule[] calldata schedules
    ) external onlyOwner {
        for (uint256 i = 0; i < schedules.length; i++) {
            _setVestingSchedule(
                schedules[i].allocationId,
                schedules[i].reserved,
                schedules[i].lockup,
                schedules[i].cliff,
                schedules[i].vesting,
                schedules[i].tgeUnlock,
                schedules[i].unlockDelay
            );
        }
    }

    /**
     * @notice Removes the vesting parameters for a specific allocation.
     * @dev Can only be called by the contract owner.
     * WARNING: This function is not synchronized with the sales stages. Ensure that the removal is in line with the sales strategy.
     * @param allocationId The ID of the allocation to remove.
     */
    function removeAllocation(bytes32 allocationId) external onlyOwner {
        _removeAllocation(allocationId);
    }

    /**
     * @notice Allows the owner to set the auto-claim status.
     * @dev Can only be called by the contract owner.
     * @param status The new status of auto-claim.
     */
    function setAutoClaimAfterTge(bool status) external onlyOwner {
        _setAutoClaimAfterTge(status);
    }

    /**
     * @notice Allows the owner to set the name and symbol of the vested token.
     * @dev Can only be called by the contract owner.
     * It sets the name and symbol of the vested token by calling a private function from the NonTransferableToken contract.
     * @param name_ The new name of the vested token.
     * @param symbol_ The new symbol of the vested token.
     */
    function setVestedTokenNameSymbol(
        string memory name_,
        string memory symbol_
    ) external onlyOwner {
        _setNonTransferableTokenNameSymbol(name_, symbol_);
    }

    /**
     * @notice Sets a new TokenSale address.
     * @dev Can only be called by the contract owner.
     * Emits a TokenSaleUpdated event.
     * @param tokenSale The address of the TokenSale.
     */
    function setTokenSale(address tokenSale) external onlyOwner {
        if (_tokenSaleFrozen) {
            revert TokenSaleIsFrozen();
        }
        _tokenSale = tokenSale;
        emit TokenSaleUpdated(tokenSale);
    }

    /**
     * @notice Freezes the TokenSale, preventing further changes.
     * @dev Can only be called by the contract owner.
     * Emits a TokenSaleFrozen event.
     */
    function freezeTokenSale() external onlyOwner {
        if (_tokenSale == address(0)) {
            revert TokenSaleIsZero();
        }
        if (_tokenSaleFrozen) {
            revert TokenSaleIsFrozen();
        }

        _tokenSaleFrozen = true;
        emit TokenSaleFrozen();
    }

    /**
     * @notice Sets the auto supply status and the address from which the tokens will be supplied.
     * @dev Can only be called by the contract owner.
     * It updates the auto supply status, the auto supply status upon claim, and the address from which the tokens will be automatically supplied.
     * @param autoSupply The new status of the auto supply (if autoSupplyOnClaim is false, then for allocating; if autoSupplyOnClaim is true, then for claiming).
     * @param autoSupplyOnClaim The new status of the auto supply upon claim (true if enabled, false if disabled).
     * @param autoSupplyFrom The address from which the tokens will be supplied.
     */
    function setAutoSupply(
        bool autoSupply,
        bool autoSupplyOnClaim,
        address autoSupplyFrom
    ) external onlyOwner {
        _autoSupply = autoSupply;
        _autoSupplyOnClaim = autoSupplyOnClaim;
        _autoSupplyFrom = autoSupplyFrom;
        emit AutoSupplyUpdated(autoSupply, autoSupplyOnClaim, autoSupplyFrom);
    }
    /**
     * @notice Supplies tokens based on the total vested and claimed tokens.
     * @dev Can only be called by the contract owner.
     * It calculates the total supply of tokens required for vesting by subtracting the total claimed tokens from the total vested tokens
     * and adjusts it based on the current token balance of the contract.
     * The tokens are supplied from the address specified in `_autoSupplyFrom`.
     * @param supplyAmount The amount of tokens to supply. If zero or greater than the required amount, the required amount will be supplied.
     */
    function supplyTokens(uint256 supplyAmount) external onlyOwner {
        _supplyTokensFrom(_autoSupplyFrom, supplyAmount, false);
    }

    /**
     * @notice Supplies reserved tokens based on the total reserved and claimed tokens.
     * @dev Can only be called by the contract owner.
     * It calculates the total supply of reserved tokens required for vesting by subtracting the total claimed tokens from the total reserved tokens
     * and adjusts it based on the current token balance of the contract.
     * The tokens are supplied from the address specified in `_autoSupplyFrom`.
     * @param supplyAmount The amount of tokens to supply. If zero or greater than the required amount, the required amount will be supplied.
     */
    function supplyReservedTokens(uint256 supplyAmount) external onlyOwner {
        _supplyTokensFrom(_autoSupplyFrom, supplyAmount, true);
    }

    /**
     * @notice Handles the purchase of tokens for a specific user during a token sale stage.
     * @dev This function is called by the TokenSale contract when tokens are purchased.
     * It verifies the allocation exists and increases the vested amount for the user.
     * @param user The address of the user purchasing tokens.
     * @param stageId The ID of the sale stage.
     * @param tokensToBuy The amount of tokens being purchased.
     * @return bool Returns true if this is successfully processed.
     */
    function onTokensPurchase(
        address user,
        uint256 stageId,
        uint256 tokensToBuy
    ) external override onlyTokenSale returns (bool) {
        if (_isAutoSupplyOnAllocatingApplicable()) {
            _supplyTokensFrom(_autoSupplyFrom, tokensToBuy, false);
        }

        _increaseUserAllocationVested(
            user,
            _computeAllocationId(stageId.toString()),
            tokensToBuy
        );
        return true;
    }

    /**
     * @notice Allocates tokens to a user's vesting allocation.
     * @dev Can only be called by the contract owner.
     * This function adds a specified amount of tokens to the vesting schedule for a given user.
     * @param user The address of the user.
     * @param allocationId The ID of the allocation.
     * @param amount The amount of tokens to add to the vesting allocation.
     * @return bool Returns true if this is successfully processed.
     */
    function allocateTokens(
        address user,
        bytes32 allocationId,
        uint256 amount
    ) external onlyOwner returns (bool) {
        _increaseUserAllocationVested(user, allocationId, amount);

        if (_isAutoSupplyOnAllocatingApplicable()) {
            _supplyTokensFrom(_autoSupplyFrom, amount, false);
        }
        return true;
    }

    /**
     * @notice Allocates tokens to multiple users' vesting allocations.
     * @dev Can only be called by the contract owner.
     * This function adds a specified amount of tokens to the vesting schedule for each user and allocation pair in the list.
     * @param allocationIds An array of allocation IDs.
     * @param users The addresses of the users.
     * @param amounts The amounts of tokens to add to the vesting allocation for each user.
     * @return bool Returns true if this is successfully processed.
     */
    function allocateTokensBatch(
        bytes32[] calldata allocationIds,
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyOwner returns (bool) {
        uint256 total = allocationIds.length;
        if (users.length != total || amounts.length != total) {
            revert ParametersMismatch();
        }

        uint256 supplyAmount;
        for (uint256 i = 0; i < total; i++) {
            _increaseUserAllocationVested(
                users[i],
                allocationIds[i],
                amounts[i]
            );
            supplyAmount += amounts[i];
        }

        if (_isAutoSupplyOnAllocatingApplicable()) {
            _supplyTokensFrom(_autoSupplyFrom, supplyAmount, false);
        }
        return true;
    }

    /**
     * @dev Private function to calculate the total supply of tokens required for vesting.
     * This function calculates the difference between the total vested tokens and the total claimed tokens,
     * and adjusts it based on the current token balance of the contract.
     * @return uint256 The amount of tokens required for vesting.
     */
    function _calculateRequiredTokensSupply()
        private
        view
        whenSellableTokenIsNotZero
        returns (uint256)
    {
        uint256 requiredSupply = _totalVested - _totalClaimed;

        uint256 balance = IERC20(_getSellableToken()).balanceOf(address(this));
        if (balance >= requiredSupply) {
            return 0;
        } else {
            return requiredSupply - balance;
        }
    }

    /**
     * @dev Private function to calculate the total supply of tokens required for vesting.
     * This function calculates the difference between the total reserved tokens and the total claimed tokens,
     * and adjusts it based on the current token balance of the contract.
     * @return uint256 The amount of tokens required for vesting.
     */
    function _calculateReservedTokensSupply()
        private
        view
        whenSellableTokenIsNotZero
        returns (uint256)
    {
        uint256 requiredSupply = _totalReserved - _totalClaimed;

        uint256 balance = IERC20(_getSellableToken()).balanceOf(address(this));
        if (balance >= requiredSupply) {
            return 0;
        } else {
            return requiredSupply - balance;
        }
    }

    /**
     * @dev Checks if auto supply is applicable for allocating by verifying that auto supply is enabled, auto supply on claim is disabled, and the auto supply address is set.
     * This function ensures that the auto supply is enabled, auto supply on claim is disabled, and the address from which tokens should be supplied is not the zero address.
     * @return bool Returns true if auto supply is applicable for allocating and the address is set, otherwise returns false.
     */
    function _isAutoSupplyOnAllocatingApplicable() private view returns (bool) {
        if (
            _autoSupply && !_autoSupplyOnClaim && _autoSupplyFrom != address(0)
        ) {
            return true;
        }
        return false;
    }

    /**
     * @dev Checks if auto supply is applicable for claiming by verifying that auto supply is enabled, auto supply on claim is enabled, and the auto supply address is set.
     * This function ensures that the auto supply is enabled, auto supply on claim is enabled, and the address from which tokens should be supplied is not the zero address.
     * @return bool Returns true if auto supply is applicable for claiming and the address is set, otherwise returns false.
     */
    function _isAutoSupplyOnClaimingApplicable() private view returns (bool) {
        if (
            _autoSupply && _autoSupplyOnClaim && _autoSupplyFrom != address(0)
        ) {
            return true;
        }
        return false;
    }

    /**
     * @dev Private function to supply tokens from a specified address.
     * This function handles the actual transfer of tokens from the specified address to the contract.
     * It calculates the required supply and performs the transfer.
     * @param from The address from which the tokens will be transferred.
     * @param supplyAmount The amount of tokens to supply.
     * @param isSupplyReserved Indicates whether the supply is for reserved tokens.
     */
    function _supplyTokensFrom(
        address from,
        uint256 supplyAmount,
        bool isSupplyReserved
    ) private {
        uint256 requiredSupply;
        if (isSupplyReserved) {
            requiredSupply = _calculateReservedTokensSupply();
        } else {
            requiredSupply = _calculateRequiredTokensSupply();
        }

        if (requiredSupply == 0) {
            return;
        }

        if (supplyAmount == 0 || supplyAmount > requiredSupply) {
            supplyAmount = requiredSupply;
        }

        IERC20 _token = IERC20(_getSellableToken());
        uint256 before = _token.balanceOf(address(this));
        // If the SellableToken is mintable, then mint here in the transferFrom function.
        _token.safeTransferFrom(from, address(this), supplyAmount);

        uint256 delta = _token.balanceOf(address(this)) - before;
        // Check and prohibition of tax tokens.
        if (delta != supplyAmount) {
            revert InvalidTokenAmount();
        }
        emit TokensSupplied(supplyAmount);
    }

    /**
     * @dev Private function to get the vesting data for a specific allocation.
     * @param allocationId The ID of the allocation.
     * @return The vesting data for the specified allocation.
     */
    function _getVesting(
        bytes32 allocationId
    ) private view returns (VestingData memory) {
        return _vesting[allocationId];
    }

    /**
     * @dev Private function to get the amount of vested tokens for a user at a specific allocation.
     * @param user The address of the user.
     * @param allocationId The ID of the vesting allocation.
     * @return The vesting data for the specified user and allocation.
     */
    function _getUserVesting(
        address user,
        bytes32 allocationId
    ) private view returns (UserVestingData memory) {
        return _userVesting[user][allocationId];
    }

    /**
     * @dev Private function to increase the vested tokens for a user at a specific allocation.
     * Mints non-transferable tokens to the user.
     * Emits a VestingAccrued event.
     * Reverts with an AllocationExceeded error if the vested amount exceeds the reserved amount.
     * @param user The address of the user.
     * @param allocationId The ID of the allocation.
     * @param amount The amount of tokens to vest.
     */
    function _increaseUserAllocationVested(
        address user,
        bytes32 allocationId,
        uint256 amount
    ) private allocationIdExists(allocationId) {
        _totalVested += amount;

        // Check if vested tokens exceed reserved tokens.
        _vesting[allocationId].vested += amount;
        if (_vesting[allocationId].vested > _vesting[allocationId].reserved) {
            revert AllocationExceeded(allocationId);
        }

        _userVesting[user][allocationId].vested += amount;
        _mintNonTransferableToken(user, amount);
        emit VestingAccrued(user, allocationId, amount);

        if (_autoClaimAfterTge && _isTgePassed()) {
            _claim(user);
        }
    }

    /**
     * @dev Private function to increase the total claimed tokens and update the user's claimed tokens.
     * Burns the corresponding amount of non-transferable tokens from the user's balance.
     * Emits a VestingClaimed event.
     * @param user The address of the user whose claimed tokens are being increased.
     * @param allocationId The ID of the allocation.
     * @param _token The sellable token used for transfer.
     * @param amount The amount of tokens to be marked as claimed.
     */
    function _claimAllocation(
        address user,
        bytes32 allocationId,
        IERC20 _token,
        uint256 amount
    ) private {
        _totalClaimed += amount;
        _vesting[allocationId].claimed += amount;

        _userVesting[user][allocationId].claimed += amount;
        _burnNonTransferableToken(user, amount);

        _token.safeTransfer(user, amount);
        emit VestingClaimed(user, allocationId, amount);
    }

    /**
     * @dev Private function to claim vested tokens for a user.
     * Transfers the claimable tokens to the user and updates the claimed tokens.
     * @param user The address of the user claiming the tokens.
     */
    function _claim(address user) private whenSellableTokenIsNotZero {
        bytes32[] memory allocationIds = _getAllocationIds();
        (
            ,
            uint256 totalClaimed,
            uint256 totalUnlocked,
            ,
            uint256[] memory claimed,
            uint256[] memory unlocked
        ) = _calculateUserVestingStateAtTime(
                allocationIds,
                user,
                block.timestamp
            );

        uint256 totalClaimable;
        if (totalUnlocked > totalClaimed) {
            totalClaimable = totalUnlocked - totalClaimed;
        }

        if (totalClaimable > 0) {
            if (_isAutoSupplyOnClaimingApplicable()) {
                _supplyTokensFrom(_autoSupplyFrom, totalClaimable, false);
            }

            IERC20 _token = IERC20(_getSellableToken());
            uint256 totalAllocations = allocationIds.length;
            for (uint256 i = 0; i < totalAllocations; i++) {
                uint256 claimable;
                if (unlocked[i] > claimed[i]) {
                    claimable = unlocked[i] - claimed[i];
                }

                if (claimable > 0) {
                    _claimAllocation(user, allocationIds[i], _token, claimable);
                }
            }
        }
    }

    /**
     * @dev Private function to calculate the unlocked vested tokens for a user at a specific time.
     * @param allocationIds An array of allocation IDs.
     * @param user The address of the user.
     * @param atTime The specific time to check for unlocked tokens.
     * @return totalVested The total amount of vested tokens.
     * @return totalClaimed The total amount of claimed tokens.
     * @return totalUnlocked The amount of unlocked vested tokens.
     * @return vested Array of vested tokens for each allocation.
     * @return claimed Array of claimed tokens for each allocation.
     * @return unlocked Array of unlocked vested tokens for each allocation.
     */
    function _calculateUserVestingStateAtTime(
        bytes32[] memory allocationIds,
        address user,
        uint256 atTime
    )
        private
        view
        returns (
            uint256 totalVested,
            uint256 totalClaimed,
            uint256 totalUnlocked,
            uint256[] memory vested,
            uint256[] memory claimed,
            uint256[] memory unlocked
        )
    {
        uint256 totalAllocations = allocationIds.length;
        vested = new uint256[](totalAllocations);
        claimed = new uint256[](totalAllocations);
        unlocked = new uint256[](totalAllocations);

        for (uint256 i = 0; i < totalAllocations; i++) {
            bytes32 allocationId = allocationIds[i];
            VestingData memory vd = _getVesting(allocationId);
            UserVestingData memory uvd = _getUserVesting(user, allocationId);

            if (uvd.vested == 0) {
                // The user does not have any tokens to vest in this allocation.
                continue;
            }
            totalVested += uvd.vested;
            totalClaimed += uvd.claimed;
            vested[i] = uvd.vested;
            claimed[i] = uvd.claimed;

            uint256 unlockedAtTime = _calculateUserUnlockedAtTime(
                vd,
                uvd,
                atTime
            );
            totalUnlocked += unlockedAtTime;
            unlocked[i] = unlockedAtTime;
        }
    }

    /**
     * @dev Private function to calculate the total amount of unlocked tokens for a user at a specific time based on vesting data.
     * @param vd The vesting data associated with the allocation.
     * @param uvd The user's vesting data for the allocation.
     * @param atTime The specific time to check for unlocked tokens.
     * @return totalUnlocked The total amount of unlocked tokens at the specified time.
     */
    function _calculateUserUnlockedAtTime(
        VestingData memory vd,
        UserVestingData memory uvd,
        uint256 atTime
    ) private view returns (uint256 totalUnlocked) {
        uint256 tge = _getTgeTimestamp();
        if (tge == 0 || atTime < tge) {
            // The TGE event has not yet occurred. Then unlocked is 0.
            return totalUnlocked;
        }

        uint256 tgeUnlocked = (uvd.vested * vd.tgeUnlock) / DENOMINATOR;
        uint256 restVested = uvd.vested - tgeUnlocked;
        totalUnlocked += tgeUnlocked;

        uint256 vestingStartTime = tge + vd.lockup;
        if (atTime < vestingStartTime) {
            // Unlocking tokens from vesting has not yet begun.
            return totalUnlocked;
        }

        uint256 cliffEndTime = vestingStartTime + vd.cliff;
        if (atTime < cliffEndTime) {
            // Unlocking of tokens has already begun, but the claim is impossible until the end of the cliff period.
            return totalUnlocked;
        }

        uint256 vestingEndTime = vestingStartTime + vd.vesting;
        if (atTime >= vestingEndTime) {
            // Vesting is done. The entire amount is available for claim.
            return uvd.vested;
        }

        if (atTime >= cliffEndTime) {
            uint256 passedTime = atTime - vestingStartTime;
            if (vd.unlockDelay > 0) {
                // Fix if the interval between claims is specified.
                uint256 unlocks = passedTime / vd.unlockDelay;
                passedTime = unlocks * vd.unlockDelay;
            }
            uint256 unlockedAtTime = (restVested * passedTime) / vd.vesting;
            totalUnlocked += unlockedAtTime;
        }
    }

    /**
     * @dev Private function to calculate the unlocked vested tokens for all allocations at a specific time.
     * @param allocationIds An array of allocation IDs.
     * @param atTime The specific time to check for unlocked tokens.
     * @return totalVested The total amount of vested tokens across all allocations.
     * @return totalClaimed The total amount of claimed tokens across all allocations.
     * @return totalUnlocked The amount of unlocked vested tokens at the specified time.
     * @return reserved Array of reserved tokens for each allocation.
     * @return vested Array of vested tokens for each allocation.
     * @return claimed Array of claimed tokens for each allocation.
     * @return unlocked Array of unlocked vested tokens for each allocation.
     */
    function _calculateVestingStateAtTime(
        bytes32[] memory allocationIds,
        uint256 atTime
    )
        private
        view
        returns (
            uint256 totalVested,
            uint256 totalClaimed,
            uint256 totalUnlocked,
            uint256[] memory reserved,
            uint256[] memory vested,
            uint256[] memory claimed,
            uint256[] memory unlocked
        )
    {
        uint256 totalAllocations = allocationIds.length;
        reserved = new uint256[](totalAllocations);
        vested = new uint256[](totalAllocations);
        claimed = new uint256[](totalAllocations);
        unlocked = new uint256[](totalAllocations);

        for (uint256 i = 0; i < totalAllocations; i++) {
            bytes32 allocationId = allocationIds[i];
            VestingData memory vd = _getVesting(allocationId);

            reserved[i] = vd.reserved;

            if (vd.vested == 0) {
                // Does not have any tokens to vest in this allocation.
                continue;
            }
            totalVested += vd.vested;
            totalClaimed += vd.claimed;
            vested[i] = vd.vested;
            claimed[i] = vd.claimed;

            uint256 unlockedAtTime = _calculateUnlockedAtTime(vd, atTime);
            totalUnlocked += unlockedAtTime;
            unlocked[i] = unlockedAtTime;
        }
    }

    /**
     * @dev Private function to calculate the total amount of unlocked tokens for a specific allocation at a specific time.
     * @param vd The vesting data associated with the allocation.
     * @param atTime The specific time to check for unlocked tokens.
     * @return totalUnlocked The total amount of unlocked tokens at the specified time.
     */
    function _calculateUnlockedAtTime(
        VestingData memory vd,
        uint256 atTime
    ) private view returns (uint256 totalUnlocked) {
        uint256 tge = _getTgeTimestamp();
        if (tge == 0 || atTime < tge) {
            // The TGE event has not yet occurred. Then unlocked is 0.
            return totalUnlocked;
        }

        uint256 tgeUnlocked = (vd.vested * vd.tgeUnlock) / DENOMINATOR;
        uint256 restVested = vd.vested - tgeUnlocked;
        totalUnlocked += tgeUnlocked;

        uint256 vestingStartTime = tge + vd.lockup;
        if (atTime < vestingStartTime) {
            // Unlocking tokens from vesting has not yet begun.
            return totalUnlocked;
        }

        uint256 cliffEndTime = vestingStartTime + vd.cliff;
        if (atTime < cliffEndTime) {
            // Unlocking of tokens has already begun, but the claim is impossible until the end of the cliff period.
            return totalUnlocked;
        }

        uint256 vestingEndTime = vestingStartTime + vd.vesting;
        if (atTime >= vestingEndTime) {
            // Vesting is done. The entire amount is available for claim.
            return vd.vested;
        }

        if (atTime >= cliffEndTime) {
            uint256 passedTime = atTime - vestingStartTime;
            if (vd.unlockDelay > 0) {
                // Fix if the interval between claims is specified.
                uint256 unlocks = passedTime / vd.unlockDelay;
                passedTime = unlocks * vd.unlockDelay;
            }
            uint256 unlockedAtTime = (restVested * passedTime) / vd.vesting;
            totalUnlocked += unlockedAtTime;
        }
    }

    /**
     * @dev Private function to set the vesting parameters for a specific allocation.
     * WARNING: This function is not synchronized with the sales stages.
     * Ensures that the vesting parameters are set in accordance with the sales strategy.
     * Ensures that the TGE unlock percentage does not exceed the maximum allowed value.
     * Emits an AllocationUpdated event.
     * @param allocationId The ID of the allocation to set the vesting parameters.
     * @param reserved The total amount of tokens reserved for this allocation.
     * @param lockup The lock-up period before vesting starts.
     * @param cliff The cliff period during which tokens cannot be claimed.
     * @param vesting The total vesting period over which tokens are gradually unlocked.
     * @param tgeUnlock The percentage of tokens unlocked immediately after the Token Generation Event (TGE).
     * @param unlockDelay The delay between successive unlocks after the cliff period.
     */
    function _setVestingSchedule(
        bytes32 allocationId,
        uint256 reserved,
        uint256 lockup,
        uint256 cliff,
        uint256 vesting,
        uint256 tgeUnlock,
        uint256 unlockDelay
    ) private {
        if (tgeUnlock > DENOMINATOR) {
            revert TgeUnlockExceedsMaximum();
        }

        if (!_isAllocationIdExist(allocationId)) {
            _allocationIds.push(allocationId);
            _allocationIdExist[allocationId] = true;
        }

        VestingData storage vestingData = _vesting[allocationId];

        if (vestingData.vested > reserved) {
            revert ReservedLessThanVested(allocationId);
        }
        _totalReserved = _totalReserved - vestingData.reserved + reserved;
        vestingData.reserved = reserved;

        vestingData.lockup = lockup;
        vestingData.cliff = cliff;
        vestingData.vesting = vesting;
        vestingData.tgeUnlock = tgeUnlock;
        vestingData.unlockDelay = unlockDelay;

        emit AllocationUpdated(
            allocationId,
            reserved,
            lockup,
            cliff,
            vesting,
            tgeUnlock,
            unlockDelay
        );
    }

    /**
     * @dev Private function to remove the vesting parameters for a specific allocation.
     * WARNING: This function is not synchronized with the sales stages. Ensure that the vesting parameters are removed in accordance with the sales strategy.
     * Emits an AllocationDeleted event.
     * @param allocationId The ID of the allocation to remove the vesting parameters for.
     */
    function _removeAllocation(bytes32 allocationId) private {
        VestingData memory vestingData = _getVesting(allocationId);
        if (vestingData.vested > 0) {
            revert AllocationAlreadyUsed();
        }

        bytes32[] memory allocationIds = _getAllocationIds();
        uint256 index = _findAllocationIndex(allocationId, allocationIds);
        uint256 lastIndex = allocationIds.length - 1;
        bytes32 lastAllocationId = _allocationIds[lastIndex];

        _allocationIds[index] = lastAllocationId; // Move the last allocation ID to the index being removed.
        _allocationIds.pop(); // Remove the last element.

        delete _vesting[allocationId];
        delete _allocationIdExist[allocationId];
        emit AllocationDeleted(allocationId);
    }

    /**
     * @dev Private function to compute the allocation ID for a given allocation name.
     * This function computes the keccak-256 hash of the given allocation name, subtracts 1, and returns it as bytes32.
     * @param allocationName The name of the allocation.
     * @return allocationId The computed ID of the allocation.
     */
    function _computeAllocationId(
        string memory allocationName
    ) private pure returns (bytes32 allocationId) {
        return
            bytes32(
                abi.encode(uint256(keccak256(abi.encode(allocationName))) - 1)
            );
    }

    /**
     * @dev Checks if a given allocation ID exists in the allowed allocation IDs list.
     * This function is used internally to verify if a specific allocation ID is present in the contract's allocation list.
     * @param allocationId The ID of the allocation to check.
     * @return bool Returns true if the allocation exists, false otherwise.
     */
    function _isAllocationIdExist(
        bytes32 allocationId
    ) private view returns (bool) {
        return _allocationIdExist[allocationId];
    }

    /**
     * @dev Checks if a given allocation ID exists in the allowed allocation IDs list and reverts if it does not exist.
     * This function is used internally to ensure that an allocation ID is valid before proceeding with further logic.
     * If the allocation does not exist, it reverts with a custom error `AllocationNotFound`.
     * @param allocationId The ID of the allocation to check.
     */
    function _checkAllocationIdExistence(bytes32 allocationId) private view {
        if (!_isAllocationIdExist(allocationId)) {
            revert AllocationNotFound(allocationId);
        }
    }

    /**
     * @dev Internal function to retrieve the list of all allowed allocation IDs.
     * @return bytes32[] List of allowed allocation IDs.
     */
    function _getAllocationIds() private view returns (bytes32[] memory) {
        return _allocationIds;
    }

    /**
     * @dev Internal function to get the total number of vesting allocations.
     * @return The total number of vesting allocations.
     */
    function _getTotalAllocations() private view returns (uint256) {
        return _allocationIds.length;
    }

    /**
     * @dev Finds the index of a given allocation in an array of allocation IDs.
     * This function searches for a specific allocation ID within an array of allocation IDs and returns its index.
     * If the allocation does not exist, it reverts with a custom error `AllocationNotFound`.
     * @param allocationId The allocation ID to find.
     * @param allocationIds An array of allocation IDs.
     * @return uint256 The index of the found allocation.
     */
    function _findAllocationIndex(
        bytes32 allocationId,
        bytes32[] memory allocationIds
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < allocationIds.length; i++) {
            if (allocationIds[i] == allocationId) {
                return i;
            }
        }
        revert AllocationNotFound(allocationId);
    }

    /**
     * @dev Private function to set the auto-claim status.
     * Emits an AutoClaimAfterTgeUpdated event.
     * @param status The new status of auto-claim.
     */
    function _setAutoClaimAfterTge(bool status) private {
        _autoClaimAfterTge = status;
        emit AutoClaimAfterTgeUpdated(status);
    }
}
