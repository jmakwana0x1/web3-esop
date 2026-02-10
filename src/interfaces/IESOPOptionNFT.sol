// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IESOPOptionNFT {
    // ==================== Struct ====================

    struct OptionGrant {
        // Slot 1: 128 + 128 = 256 bits
        uint128 totalOptions;
        uint128 exercisedOptions;
        // Slot 2: 128 + 64 + 64 = 256 bits
        uint128 strikePrice;
        uint64 vestingStart;
        uint64 cliffDuration;
        // Slot 3: 64 + 64 + 64 + 8 = 200 bits
        uint64 vestingDuration;
        uint64 terminationTimestamp;
        uint64 postTerminationWindow;
        bool terminated;
    }

    // ==================== Errors ====================

    error InvalidGrantParameters();
    error GrantNotFound(uint256 tokenId);
    error GrantAlreadyTerminated(uint256 tokenId);
    error GrantExpired(uint256 tokenId);
    error NothingToExercise(uint256 tokenId);
    error ExerciseAmountExceedsAvailable(uint256 tokenId, uint128 requested, uint128 available);
    error ExerciseWindowClosed(uint256 tokenId);
    error TransferNotApprovedByAdmin(uint256 tokenId, address from, address to);
    error ZeroAddress();
    error ZeroAmount();
    error GrantNotBurnable(uint256 tokenId);

    // ==================== Events ====================

    event GrantCreated(
        uint256 indexed tokenId,
        address indexed employee,
        uint128 totalOptions,
        uint128 strikePrice,
        uint64 vestingStart,
        uint64 cliffDuration,
        uint64 vestingDuration,
        uint64 postTerminationWindow
    );

    event OptionsExercised(
        uint256 indexed tokenId, address indexed employee, uint128 optionsExercised, uint256 usdcPaid, uint256 tokensMinted
    );

    event GrantTerminated(
        uint256 indexed tokenId,
        address indexed employee,
        uint64 terminationTimestamp,
        uint128 vestedAtTermination,
        uint128 unvestedLost
    );

    event GrantBurned(uint256 indexed tokenId, address indexed employee);

    event AdminTransferApproved(uint256 indexed tokenId, address indexed from, address indexed to);

    event AdminTransferRevoked(uint256 indexed tokenId);

    event USDCTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ==================== Functions ====================

    function grantOptions(
        address employee,
        uint128 totalOptions,
        uint128 strikePrice,
        uint64 vestingStart,
        uint64 cliffDuration,
        uint64 vestingDuration,
        uint64 postTerminationWindow
    ) external returns (uint256 tokenId);

    function exercise(uint256 tokenId, uint128 amount) external;

    function terminateGrant(uint256 tokenId) external;

    function burnGrant(uint256 tokenId) external;

    function approveTransfer(uint256 tokenId, address to) external;

    function revokeTransferApproval(uint256 tokenId) external;

    function executeApprovedTransfer(uint256 tokenId) external;

    function getGrant(uint256 tokenId) external view returns (OptionGrant memory);

    function getVestedOptions(uint256 tokenId) external view returns (uint128);

    function getExercisableOptions(uint256 tokenId) external view returns (uint128);

    function getExerciseCost(uint256 tokenId, uint128 amount) external view returns (uint256);

    function isGrantExpired(uint256 tokenId) external view returns (bool);

    function isGrantFullyExercised(uint256 tokenId) external view returns (bool);

    function setUSDCTreasury(address newTreasury) external;
}
