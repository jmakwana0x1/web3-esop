// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./Base.t.sol";
import {IESOPOptionNFT} from "../src/interfaces/IESOPOptionNFT.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ESOPOptionNFTTest is BaseTest {
    bytes32 internal grantorRole;
    bytes32 internal adminRole;

    function setUp() public override {
        super.setUp();
        grantorRole = optionNFT.GRANTOR_ROLE();
        adminRole = optionNFT.ADMIN_ROLE();
    }

    // ==================== Grant Creation ====================

    function test_GrantOptions_Success_MintsNFTToEmployee() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        assertEq(optionNFT.ownerOf(tokenId), employee1);
    }

    function test_GrantOptions_Success_StoresCorrectGrantData() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);

        assertEq(grant.totalOptions, DEFAULT_OPTIONS);
        assertEq(grant.exercisedOptions, 0);
        assertEq(grant.strikePrice, DEFAULT_STRIKE);
        assertEq(grant.cliffDuration, DEFAULT_CLIFF);
        assertEq(grant.vestingDuration, DEFAULT_VESTING);
        assertEq(grant.postTerminationWindow, DEFAULT_POST_TERM_WINDOW);
        assertFalse(grant.terminated);
    }

    function test_GrantOptions_Success_EmitsGrantCreatedEvent() public {
        vm.prank(grantor);
        vm.expectEmit(true, true, true, true);
        emit IESOPOptionNFT.GrantCreated(
            1,
            employee1,
            DEFAULT_OPTIONS,
            DEFAULT_STRIKE,
            uint64(block.timestamp),
            DEFAULT_CLIFF,
            DEFAULT_VESTING,
            DEFAULT_POST_TERM_WINDOW
        );
        optionNFT.grantOptions(
            employee1,
            DEFAULT_OPTIONS,
            DEFAULT_STRIKE,
            uint64(block.timestamp),
            DEFAULT_CLIFF,
            DEFAULT_VESTING,
            DEFAULT_POST_TERM_WINDOW
        );
    }

    function test_GrantOptions_Success_IncrementsTokenId() public {
        uint256 id1 = _createDefaultGrant(employee1);
        uint256 id2 = _createDefaultGrant(employee2);
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_GrantOptions_Success_MultipleGrantsToSameEmployee() public {
        uint256 id1 = _createDefaultGrant(employee1);
        uint256 id2 = _createDefaultGrant(employee1);
        assertEq(optionNFT.balanceOf(employee1), 2);
        assertEq(optionNFT.ownerOf(id1), employee1);
        assertEq(optionNFT.ownerOf(id2), employee1);
    }

    function test_GrantOptions_RevertWhen_CallerLacksGrantorRole() public {
        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, employee1, grantorRole)
        );
        optionNFT.grantOptions(
            employee1, DEFAULT_OPTIONS, DEFAULT_STRIKE, uint64(block.timestamp), DEFAULT_CLIFF, DEFAULT_VESTING, DEFAULT_POST_TERM_WINDOW
        );
    }

    function test_GrantOptions_RevertWhen_EmployeeIsZeroAddress() public {
        vm.prank(grantor);
        vm.expectRevert(IESOPOptionNFT.ZeroAddress.selector);
        optionNFT.grantOptions(
            address(0), DEFAULT_OPTIONS, DEFAULT_STRIKE, uint64(block.timestamp), DEFAULT_CLIFF, DEFAULT_VESTING, DEFAULT_POST_TERM_WINDOW
        );
    }

    function test_GrantOptions_RevertWhen_TotalOptionsIsZero() public {
        vm.prank(grantor);
        vm.expectRevert(IESOPOptionNFT.InvalidGrantParameters.selector);
        optionNFT.grantOptions(
            employee1, 0, DEFAULT_STRIKE, uint64(block.timestamp), DEFAULT_CLIFF, DEFAULT_VESTING, DEFAULT_POST_TERM_WINDOW
        );
    }

    function test_GrantOptions_RevertWhen_VestingDurationLessThanCliff() public {
        vm.prank(grantor);
        vm.expectRevert(IESOPOptionNFT.InvalidGrantParameters.selector);
        optionNFT.grantOptions(
            employee1,
            DEFAULT_OPTIONS,
            DEFAULT_STRIKE,
            uint64(block.timestamp),
            DEFAULT_VESTING, // cliff > vesting
            DEFAULT_CLIFF,
            DEFAULT_POST_TERM_WINDOW
        );
    }

    function test_GrantOptions_RevertWhen_StrikePriceIsZero() public {
        vm.prank(grantor);
        vm.expectRevert(IESOPOptionNFT.InvalidGrantParameters.selector);
        optionNFT.grantOptions(
            employee1, DEFAULT_OPTIONS, 0, uint64(block.timestamp), DEFAULT_CLIFF, DEFAULT_VESTING, DEFAULT_POST_TERM_WINDOW
        );
    }

    function test_GrantOptions_RevertWhen_PostTerminationWindowIsZero() public {
        vm.prank(grantor);
        vm.expectRevert(IESOPOptionNFT.InvalidGrantParameters.selector);
        optionNFT.grantOptions(employee1, DEFAULT_OPTIONS, DEFAULT_STRIKE, uint64(block.timestamp), DEFAULT_CLIFF, DEFAULT_VESTING, 0);
    }

    // ==================== Exercise ====================

    function test_Exercise_Success_FullExerciseAfterFullVesting() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        _approveAndExercise(employee1, tokenId, DEFAULT_OPTIONS);

        assertEq(esopToken.balanceOf(employee1), uint256(DEFAULT_OPTIONS) * 1e18);
        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
        assertEq(grant.exercisedOptions, DEFAULT_OPTIONS);
    }

    function test_Exercise_Success_PartialExercise() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        _approveAndExercise(employee1, tokenId, 5000);

        assertEq(esopToken.balanceOf(employee1), 5000 * 1e18);
        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
        assertEq(grant.exercisedOptions, 5000);
    }

    function test_Exercise_Success_MultiplePartialExercises() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        _approveAndExercise(employee1, tokenId, 3000);
        _approveAndExercise(employee1, tokenId, 3000);
        _approveAndExercise(employee1, tokenId, 4000);

        assertEq(esopToken.balanceOf(employee1), uint256(DEFAULT_OPTIONS) * 1e18);
    }

    function test_Exercise_Success_TransfersCorrectUSDC() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 employeeBefore = usdc.balanceOf(employee1);

        uint128 amount = 1000;
        uint256 expectedCost = uint256(amount) * uint256(DEFAULT_STRIKE);

        _approveAndExercise(employee1, tokenId, amount);

        assertEq(usdc.balanceOf(treasury), treasuryBefore + expectedCost);
        assertEq(usdc.balanceOf(employee1), employeeBefore - expectedCost);
    }

    function test_Exercise_Success_MintsCorrectTokens() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        uint128 amount = 2500;
        _approveAndExercise(employee1, tokenId, amount);

        assertEq(esopToken.balanceOf(employee1), uint256(amount) * 1e18);
    }

    function test_Exercise_Success_EmitsOptionsExercisedEvent() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        uint128 amount = 1000;
        uint256 cost = uint256(amount) * uint256(DEFAULT_STRIKE);
        uint256 tokens = uint256(amount) * 1e18;

        vm.startPrank(employee1);
        usdc.approve(address(optionNFT), cost);

        vm.expectEmit(true, true, true, true);
        emit IESOPOptionNFT.OptionsExercised(tokenId, employee1, amount, cost, tokens);
        optionNFT.exercise(tokenId, amount);
        vm.stopPrank();
    }

    function test_Exercise_RevertWhen_CallerDoesNotOwnNFT() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(employee2);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.GrantNotFound.selector, tokenId));
        optionNFT.exercise(tokenId, 1000);
    }

    function test_Exercise_RevertWhen_BeforeCliff() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        vm.warp(block.timestamp + DEFAULT_CLIFF - 1);

        vm.prank(employee1);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.NothingToExercise.selector, tokenId));
        optionNFT.exercise(tokenId, 1);
    }

    function test_Exercise_RevertWhen_AmountExceedsExercisable() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToCliff();

        // At cliff: 25% vested = 2500
        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IESOPOptionNFT.ExerciseAmountExceedsAvailable.selector, tokenId, 5000, 2500)
        );
        optionNFT.exercise(tokenId, 5000);
    }

    function test_Exercise_RevertWhen_ZeroAmount() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(employee1);
        vm.expectRevert(IESOPOptionNFT.ZeroAmount.selector);
        optionNFT.exercise(tokenId, 0);
    }

    function test_Exercise_RevertWhen_InsufficientUSDCAllowance() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(employee1);
        // No USDC approval
        vm.expectRevert();
        optionNFT.exercise(tokenId, 1000);
    }

    function test_Exercise_RevertWhen_Paused() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(admin);
        optionNFT.pause();

        vm.prank(employee1);
        vm.expectRevert();
        optionNFT.exercise(tokenId, 1000);
    }

    function test_Exercise_RevertWhen_FullyExercised() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        _approveAndExercise(employee1, tokenId, DEFAULT_OPTIONS);

        vm.prank(employee1);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.NothingToExercise.selector, tokenId));
        optionNFT.exercise(tokenId, 1);
    }

    // ==================== Termination ====================

    function test_Terminate_Success_SetsTerminatedFlag() public {
        uint256 tokenId = _createDefaultGrant(employee1);

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
        assertTrue(grant.terminated);
    }

    function test_Terminate_Success_RecordsTerminationTimestamp() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        vm.warp(block.timestamp + 200 days);

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
        assertEq(grant.terminationTimestamp, uint64(block.timestamp));
    }

    function test_Terminate_Success_EmitsGrantTerminatedEvent() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days); // 2 years in

        // At 2 years: 50% vested = 5000
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IESOPOptionNFT.GrantTerminated(tokenId, employee1, uint64(block.timestamp), 5000, 5000);
        optionNFT.terminateGrant(tokenId);
    }

    function test_Terminate_RevertWhen_CallerLacksAdminRole() public {
        uint256 tokenId = _createDefaultGrant(employee1);

        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, employee1, adminRole)
        );
        optionNFT.terminateGrant(tokenId);
    }

    function test_Terminate_RevertWhen_AlreadyTerminated() public {
        uint256 tokenId = _createDefaultGrant(employee1);

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.GrantAlreadyTerminated.selector, tokenId));
        optionNFT.terminateGrant(tokenId);
    }

    function test_Terminate_BeforeCliff_AllOptionsLost() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        vm.warp(block.timestamp + 100 days); // Before cliff

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IESOPOptionNFT.GrantTerminated(tokenId, employee1, uint64(block.timestamp), 0, DEFAULT_OPTIONS);
        optionNFT.terminateGrant(tokenId);
    }

    function test_Terminate_AfterFullVesting_AllOptionsVested() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IESOPOptionNFT.GrantTerminated(tokenId, employee1, uint64(block.timestamp), DEFAULT_OPTIONS, 0);
        optionNFT.terminateGrant(tokenId);
    }

    // ==================== Post-Termination Exercise ====================

    function test_ExerciseAfterTermination_Success_WithinWindow() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days); // 2 years = 50% = 5000 vested

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Exercise within post-termination window
        vm.warp(block.timestamp + 30 days); // 30 days after termination
        _approveAndExercise(employee1, tokenId, 5000);

        assertEq(esopToken.balanceOf(employee1), 5000 * 1e18);
    }

    function test_ExerciseAfterTermination_VestedCappedAtTermination() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days); // 2 years = 50% = 5000 vested

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Even though more time passes, vested is capped at termination
        vm.warp(block.timestamp + 30 days);
        uint128 exercisable = optionNFT.getExercisableOptions(tokenId);
        assertEq(exercisable, 5000);
    }

    function test_ExerciseAfterTermination_RevertWhen_WindowExpired() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days);

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Warp past post-termination window
        vm.warp(block.timestamp + DEFAULT_POST_TERM_WINDOW + 1);

        vm.prank(employee1);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.GrantExpired.selector, tokenId));
        optionNFT.exercise(tokenId, 1);
    }

    function test_ExerciseAfterTermination_UnvestedNotExercisable() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days); // 5000 vested

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        vm.warp(block.timestamp + 10 days);

        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IESOPOptionNFT.ExerciseAmountExceedsAvailable.selector, tokenId, 5001, 5000)
        );
        optionNFT.exercise(tokenId, 5001);
    }

    // ==================== Soulbound Transfer ====================

    function test_Transfer_RevertWhen_DirectTransfer() public {
        uint256 tokenId = _createDefaultGrant(employee1);

        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IESOPOptionNFT.TransferNotApprovedByAdmin.selector, tokenId, employee1, employee2)
        );
        optionNFT.transferFrom(employee1, employee2, tokenId);
    }

    function test_Transfer_RevertWhen_SafeTransferFrom() public {
        uint256 tokenId = _createDefaultGrant(employee1);

        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IESOPOptionNFT.TransferNotApprovedByAdmin.selector, tokenId, employee1, employee2)
        );
        optionNFT.safeTransferFrom(employee1, employee2, tokenId);
    }

    function test_Transfer_Success_AfterAdminApproval() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        address newWallet = makeAddr("newWallet");

        // Admin approves transfer
        vm.prank(admin);
        optionNFT.approveTransfer(tokenId, newWallet);

        // Execute transfer
        vm.prank(employee1);
        optionNFT.executeApprovedTransfer(tokenId);

        assertEq(optionNFT.ownerOf(tokenId), newWallet);
    }

    function test_Transfer_Success_GrantDataPreservedAfterTransfer() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        address newWallet = makeAddr("newWallet");

        vm.prank(admin);
        optionNFT.approveTransfer(tokenId, newWallet);

        vm.prank(employee1);
        optionNFT.executeApprovedTransfer(tokenId);

        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
        assertEq(grant.totalOptions, DEFAULT_OPTIONS);
        assertEq(grant.exercisedOptions, 0);
    }

    function test_Transfer_RevertWhen_ApprovedToWrongAddress() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        address newWallet = makeAddr("newWallet");
        address wrongWallet = makeAddr("wrongWallet");

        vm.prank(admin);
        optionNFT.approveTransfer(tokenId, newWallet);

        // Try to transfer to wrong address via direct transferFrom
        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IESOPOptionNFT.TransferNotApprovedByAdmin.selector, tokenId, employee1, wrongWallet
            )
        );
        optionNFT.transferFrom(employee1, wrongWallet, tokenId);
    }

    function test_Transfer_AdminCanExecuteTransfer() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        address newWallet = makeAddr("newWallet");

        vm.prank(admin);
        optionNFT.approveTransfer(tokenId, newWallet);

        // Admin executes on behalf
        vm.prank(admin);
        optionNFT.executeApprovedTransfer(tokenId);

        assertEq(optionNFT.ownerOf(tokenId), newWallet);
    }

    function test_Transfer_RevokeApproval() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        address newWallet = makeAddr("newWallet");

        vm.prank(admin);
        optionNFT.approveTransfer(tokenId, newWallet);

        vm.prank(admin);
        optionNFT.revokeTransferApproval(tokenId);

        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IESOPOptionNFT.TransferNotApprovedByAdmin.selector, tokenId, employee1, address(0))
        );
        optionNFT.executeApprovedTransfer(tokenId);
    }

    // ==================== Burn ====================

    function test_Burn_Success_FullyExercisedGrant() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();
        _approveAndExercise(employee1, tokenId, DEFAULT_OPTIONS);

        vm.prank(employee1);
        optionNFT.burnGrant(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        optionNFT.ownerOf(tokenId);
    }

    function test_Burn_Success_ExpiredTerminatedGrant() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days);

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Warp past post-termination window
        vm.warp(block.timestamp + DEFAULT_POST_TERM_WINDOW + 1);

        vm.prank(employee1);
        optionNFT.burnGrant(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        optionNFT.ownerOf(tokenId);
    }

    function test_Burn_Success_AdminCanBurn() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();
        _approveAndExercise(employee1, tokenId, DEFAULT_OPTIONS);

        vm.prank(admin);
        optionNFT.burnGrant(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        optionNFT.ownerOf(tokenId);
    }

    function test_Burn_RevertWhen_GrantStillActive() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(employee1);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.GrantNotBurnable.selector, tokenId));
        optionNFT.burnGrant(tokenId);
    }

    function test_Burn_RevertWhen_WithinPostTermWindow() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days);

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Still within window, and not all vested options exercised
        vm.warp(block.timestamp + 30 days);

        vm.prank(employee1);
        vm.expectRevert(abi.encodeWithSelector(IESOPOptionNFT.GrantNotBurnable.selector, tokenId));
        optionNFT.burnGrant(tokenId);
    }

    function test_Burn_Success_TerminatedAndVestedExercised() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;
        vm.warp(grantStart + 730 days); // 5000 vested

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Exercise all vested options
        vm.warp(block.timestamp + 10 days);
        _approveAndExercise(employee1, tokenId, 5000);

        // Can burn now since all vested options are exercised
        vm.prank(employee1);
        optionNFT.burnGrant(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        optionNFT.ownerOf(tokenId);
    }

    // ==================== View Functions ====================

    function test_GetVestedOptions_AtVariousTimestamps() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;

        // Before cliff
        assertEq(optionNFT.getVestedOptions(tokenId), 0);

        // At cliff
        vm.warp(grantStart + DEFAULT_CLIFF);
        assertEq(optionNFT.getVestedOptions(tokenId), 2500);

        // At 2 years
        vm.warp(grantStart + 730 days);
        assertEq(optionNFT.getVestedOptions(tokenId), 5000);

        // At 3 years
        vm.warp(grantStart + 1095 days);
        assertEq(optionNFT.getVestedOptions(tokenId), 7500);

        // At 4 years (full)
        vm.warp(grantStart + DEFAULT_VESTING);
        assertEq(optionNFT.getVestedOptions(tokenId), DEFAULT_OPTIONS);
    }

    function test_GetExercisableOptions_AfterPartialExercise() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        assertEq(optionNFT.getExercisableOptions(tokenId), DEFAULT_OPTIONS);

        _approveAndExercise(employee1, tokenId, 4000);
        assertEq(optionNFT.getExercisableOptions(tokenId), 6000);
    }

    function test_GetExerciseCost_CorrectCalculation() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 cost = optionNFT.getExerciseCost(tokenId, 1000);
        assertEq(cost, 1000 * uint256(DEFAULT_STRIKE));
    }

    function test_IsGrantExpired_NotTerminated() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        assertFalse(optionNFT.isGrantExpired(tokenId));
    }

    function test_IsGrantExpired_TerminatedWithinWindow() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToCliff();

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        assertFalse(optionNFT.isGrantExpired(tokenId));
    }

    function test_IsGrantExpired_TerminatedAfterWindow() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToCliff();

        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        vm.warp(block.timestamp + DEFAULT_POST_TERM_WINDOW + 1);
        assertTrue(optionNFT.isGrantExpired(tokenId));
    }

    function test_IsGrantFullyExercised() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        assertFalse(optionNFT.isGrantFullyExercised(tokenId));
        _approveAndExercise(employee1, tokenId, DEFAULT_OPTIONS);
        assertTrue(optionNFT.isGrantFullyExercised(tokenId));
    }

    // ==================== Admin Functions ====================

    function test_SetUSDCTreasury_Success() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IESOPOptionNFT.USDCTreasuryUpdated(treasury, newTreasury);
        optionNFT.setUSDCTreasury(newTreasury);

        assertEq(optionNFT.usdcTreasury(), newTreasury);
    }

    function test_SetUSDCTreasury_RevertWhen_NonAdmin() public {
        vm.prank(employee1);
        vm.expectRevert();
        optionNFT.setUSDCTreasury(makeAddr("newTreasury"));
    }

    function test_SetUSDCTreasury_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IESOPOptionNFT.ZeroAddress.selector);
        optionNFT.setUSDCTreasury(address(0));
    }

    function test_Pause_BlocksExercise() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(admin);
        optionNFT.pause();

        vm.prank(employee1);
        vm.expectRevert();
        optionNFT.exercise(tokenId, 1000);
    }

    function test_Unpause_AllowsExercise() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToFullVesting();

        vm.prank(admin);
        optionNFT.pause();

        vm.prank(admin);
        optionNFT.unpause();

        _approveAndExercise(employee1, tokenId, 1000);
        assertEq(esopToken.balanceOf(employee1), 1000 * 1e18);
    }

    function test_Pause_RevertWhen_NonAdmin() public {
        vm.prank(employee1);
        vm.expectRevert();
        optionNFT.pause();
    }
}
