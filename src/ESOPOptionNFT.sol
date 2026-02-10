// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IESOPOptionNFT} from "./interfaces/IESOPOptionNFT.sol";
import {IESOPToken} from "./interfaces/IESOPToken.sol";
import {VestingMath} from "./libraries/VestingMath.sol";

/// @title ESOPOptionNFT
/// @notice Soulbound ERC721 representing employee stock option grants.
/// @dev Each NFT stores per-grant vesting data. Tokens are non-transferable except via admin approval.
contract ESOPOptionNFT is ERC721, ERC721Enumerable, AccessControl, ReentrancyGuard, Pausable, IESOPOptionNFT {
    using SafeERC20 for IERC20;

    // ==================== Roles ====================

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GRANTOR_ROLE = keccak256("GRANTOR_ROLE");

    // ==================== State ====================

    IESOPToken public immutable esopToken;
    IERC20 public immutable usdc;
    address public usdcTreasury;

    mapping(uint256 tokenId => OptionGrant) private _grants;
    mapping(uint256 tokenId => address approvedDestination) private _adminTransferApprovals;

    uint256 private _nextTokenId = 1;

    // ==================== Constructor ====================

    /// @param name NFT collection name
    /// @param symbol NFT collection symbol
    /// @param esopTokenAddress Address of the ESOPToken (ERC20) contract
    /// @param usdcAddress Address of the USDC token contract
    /// @param treasury Address where USDC exercise payments are sent
    /// @param admin Admin address (expected to be a multi-sig)
    constructor(
        string memory name,
        string memory symbol,
        address esopTokenAddress,
        address usdcAddress,
        address treasury,
        address admin
    ) ERC721(name, symbol) {
        if (esopTokenAddress == address(0)) revert ZeroAddress();
        if (usdcAddress == address(0)) revert ZeroAddress();
        if (treasury == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        esopToken = IESOPToken(esopTokenAddress);
        usdc = IERC20(usdcAddress);
        usdcTreasury = treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(GRANTOR_ROLE, admin);
    }

    // ==================== Grant Management ====================

    /// @inheritdoc IESOPOptionNFT
    function grantOptions(
        address employee,
        uint128 totalOptions,
        uint128 strikePrice,
        uint64 vestingStart,
        uint64 cliffDuration,
        uint64 vestingDuration,
        uint64 postTerminationWindow
    ) external onlyRole(GRANTOR_ROLE) returns (uint256 tokenId) {
        if (employee == address(0)) revert ZeroAddress();
        if (totalOptions == 0) revert InvalidGrantParameters();
        if (strikePrice == 0) revert InvalidGrantParameters();
        if (vestingDuration == 0) revert InvalidGrantParameters();
        if (vestingDuration < cliffDuration) revert InvalidGrantParameters();
        if (postTerminationWindow == 0) revert InvalidGrantParameters();

        tokenId = _nextTokenId++;

        _grants[tokenId] = OptionGrant({
            totalOptions: totalOptions,
            exercisedOptions: 0,
            strikePrice: strikePrice,
            vestingStart: vestingStart,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            terminationTimestamp: 0,
            postTerminationWindow: postTerminationWindow,
            terminated: false
        });

        _safeMint(employee, tokenId);

        emit GrantCreated(
            tokenId, employee, totalOptions, strikePrice, vestingStart, cliffDuration, vestingDuration, postTerminationWindow
        );
    }

    // ==================== Exercise ====================

    /// @inheritdoc IESOPOptionNFT
    function exercise(uint256 tokenId, uint128 amount) external nonReentrant whenNotPaused {
        address holder = _requireOwned(tokenId);
        if (holder != msg.sender) revert GrantNotFound(tokenId);
        if (amount == 0) revert ZeroAmount();

        OptionGrant storage grant = _grants[tokenId];

        // Check if expired
        if (_isExpired(grant)) revert GrantExpired(tokenId);

        // Effective timestamp: cap at termination if terminated
        uint64 effectiveTimestamp = grant.terminated ? grant.terminationTimestamp : uint64(block.timestamp);

        // Calculate vested and exercisable
        uint128 vested = VestingMath.calculateVested(
            grant.totalOptions, grant.vestingStart, grant.cliffDuration, grant.vestingDuration, effectiveTimestamp
        );
        uint128 exercisable = VestingMath.calculateExercisable(vested, grant.exercisedOptions);

        if (exercisable == 0) revert NothingToExercise(tokenId);
        if (amount > exercisable) revert ExerciseAmountExceedsAvailable(tokenId, amount, exercisable);

        // Check post-termination window
        if (grant.terminated) {
            if (uint64(block.timestamp) > grant.terminationTimestamp + grant.postTerminationWindow) {
                revert ExerciseWindowClosed(tokenId);
            }
        }

        // Calculate cost
        uint256 cost = VestingMath.calculateExerciseCost(amount, grant.strikePrice);

        // Update state BEFORE external calls (CEI pattern)
        grant.exercisedOptions += amount;

        // Transfer USDC from employee to treasury
        usdc.safeTransferFrom(msg.sender, usdcTreasury, cost);

        // Mint ESOP tokens: 1 option = 1 token (18 decimals)
        uint256 tokensToMint = uint256(amount) * 1e18;
        esopToken.mint(msg.sender, tokensToMint);

        emit OptionsExercised(tokenId, msg.sender, amount, cost, tokensToMint);
    }

    // ==================== Termination ====================

    /// @inheritdoc IESOPOptionNFT
    function terminateGrant(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        _requireOwned(tokenId);
        OptionGrant storage grant = _grants[tokenId];

        if (grant.terminated) revert GrantAlreadyTerminated(tokenId);

        grant.terminated = true;
        grant.terminationTimestamp = uint64(block.timestamp);

        uint128 vestedAtTermination = VestingMath.calculateVested(
            grant.totalOptions,
            grant.vestingStart,
            grant.cliffDuration,
            grant.vestingDuration,
            uint64(block.timestamp)
        );
        uint128 unvestedLost = grant.totalOptions - vestedAtTermination;

        emit GrantTerminated(tokenId, ownerOf(tokenId), uint64(block.timestamp), vestedAtTermination, unvestedLost);
    }

    // ==================== Burn ====================

    /// @inheritdoc IESOPOptionNFT
    function burnGrant(uint256 tokenId) external {
        address holder = _requireOwned(tokenId);
        bool isAdmin = hasRole(ADMIN_ROLE, msg.sender);

        // Caller must be holder or admin
        if (holder != msg.sender && !isAdmin) revert GrantNotFound(tokenId);

        OptionGrant storage grant = _grants[tokenId];

        // Grant is burnable if:
        // 1. Fully exercised (exercisedOptions == totalOptions), OR
        // 2. Terminated AND post-termination window has passed, OR
        // 3. Terminated AND all vested options have been exercised
        bool fullyExercised = grant.exercisedOptions == grant.totalOptions;

        bool terminatedAndWindowClosed = grant.terminated
            && uint64(block.timestamp) > grant.terminationTimestamp + grant.postTerminationWindow;

        bool terminatedAndVestedExercised = false;
        if (grant.terminated) {
            uint128 vestedAtTermination = VestingMath.calculateVested(
                grant.totalOptions,
                grant.vestingStart,
                grant.cliffDuration,
                grant.vestingDuration,
                grant.terminationTimestamp
            );
            terminatedAndVestedExercised = grant.exercisedOptions >= vestedAtTermination;
        }

        if (!fullyExercised && !terminatedAndWindowClosed && !terminatedAndVestedExercised) {
            revert GrantNotBurnable(tokenId);
        }

        delete _grants[tokenId];
        delete _adminTransferApprovals[tokenId];
        _burn(tokenId);

        emit GrantBurned(tokenId, holder);
    }

    // ==================== Admin Transfer (Wallet Recovery) ====================

    /// @inheritdoc IESOPOptionNFT
    function approveTransfer(uint256 tokenId, address to) external onlyRole(ADMIN_ROLE) {
        _requireOwned(tokenId);
        if (to == address(0)) revert ZeroAddress();

        _adminTransferApprovals[tokenId] = to;

        emit AdminTransferApproved(tokenId, ownerOf(tokenId), to);
    }

    /// @inheritdoc IESOPOptionNFT
    function revokeTransferApproval(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        _requireOwned(tokenId);
        delete _adminTransferApprovals[tokenId];

        emit AdminTransferRevoked(tokenId);
    }

    /// @inheritdoc IESOPOptionNFT
    function executeApprovedTransfer(uint256 tokenId) external {
        address holder = _requireOwned(tokenId);
        address destination = _adminTransferApprovals[tokenId];

        // Caller must be the holder or an admin
        bool isAdmin = hasRole(ADMIN_ROLE, msg.sender);
        if (holder != msg.sender && !isAdmin) revert GrantNotFound(tokenId);

        if (destination == address(0)) revert TransferNotApprovedByAdmin(tokenId, holder, address(0));

        // Clear approval before transfer
        delete _adminTransferApprovals[tokenId];

        // Perform the transfer (goes through _update which allows admin-approved transfers)
        // We set the approval mapping entry back temporarily for the _update check
        _adminTransferApprovals[tokenId] = destination;
        _transfer(holder, destination, tokenId);
    }

    // ==================== View Functions ====================

    /// @inheritdoc IESOPOptionNFT
    function getGrant(uint256 tokenId) external view returns (OptionGrant memory) {
        _requireOwned(tokenId);
        return _grants[tokenId];
    }

    /// @inheritdoc IESOPOptionNFT
    function getVestedOptions(uint256 tokenId) external view returns (uint128) {
        _requireOwned(tokenId);
        OptionGrant storage grant = _grants[tokenId];

        uint64 effectiveTimestamp = grant.terminated ? grant.terminationTimestamp : uint64(block.timestamp);

        return VestingMath.calculateVested(
            grant.totalOptions, grant.vestingStart, grant.cliffDuration, grant.vestingDuration, effectiveTimestamp
        );
    }

    /// @inheritdoc IESOPOptionNFT
    function getExercisableOptions(uint256 tokenId) external view returns (uint128) {
        _requireOwned(tokenId);
        OptionGrant storage grant = _grants[tokenId];

        if (_isExpired(grant)) return 0;

        uint64 effectiveTimestamp = grant.terminated ? grant.terminationTimestamp : uint64(block.timestamp);

        uint128 vested = VestingMath.calculateVested(
            grant.totalOptions, grant.vestingStart, grant.cliffDuration, grant.vestingDuration, effectiveTimestamp
        );
        return VestingMath.calculateExercisable(vested, grant.exercisedOptions);
    }

    /// @inheritdoc IESOPOptionNFT
    function getExerciseCost(uint256 tokenId, uint128 amount) external view returns (uint256) {
        _requireOwned(tokenId);
        return VestingMath.calculateExerciseCost(amount, _grants[tokenId].strikePrice);
    }

    /// @inheritdoc IESOPOptionNFT
    function isGrantExpired(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return _isExpired(_grants[tokenId]);
    }

    /// @inheritdoc IESOPOptionNFT
    function isGrantFullyExercised(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        OptionGrant storage grant = _grants[tokenId];
        return grant.exercisedOptions == grant.totalOptions;
    }

    // ==================== Admin Functions ====================

    /// @inheritdoc IESOPOptionNFT
    function setUSDCTreasury(address newTreasury) external onlyRole(ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        address old = usdcTreasury;
        usdcTreasury = newTreasury;
        emit USDCTreasuryUpdated(old, newTreasury);
    }

    /// @notice Pauses exercise operations.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses exercise operations.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ==================== Internal ====================

    /// @dev Returns true if a terminated grant's exercise window has closed.
    function _isExpired(OptionGrant storage grant) internal view returns (bool) {
        if (!grant.terminated) return false;
        return uint64(block.timestamp) > grant.terminationTimestamp + grant.postTerminationWindow;
    }

    /// @dev Soulbound enforcement. Blocks all transfers except minting, burning, and admin-approved.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            // This is a transfer -- must be admin-approved
            address approvedTo = _adminTransferApprovals[tokenId];
            if (approvedTo == address(0) || approvedTo != to) {
                revert TransferNotApprovedByAdmin(tokenId, from, to);
            }
            // Clear approval after use
            delete _adminTransferApprovals[tokenId];
        }

        return super._update(to, tokenId, auth);
    }

    /// @dev Required override for ERC721Enumerable.
    function _increaseBalance(address account, uint128 amount) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, amount);
    }

    /// @dev Required override to resolve ERC165 conflict.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
