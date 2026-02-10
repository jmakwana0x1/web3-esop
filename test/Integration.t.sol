// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./Base.t.sol";
import {IESOPOptionNFT} from "../src/interfaces/IESOPOptionNFT.sol";

contract IntegrationTest is BaseTest {
    function test_E2E_FullLifecycle_GrantVestExercise() public {
        // 1. Grant options
        uint256 grantStart = block.timestamp;
        uint256 tokenId = _createDefaultGrant(employee1);
        assertEq(optionNFT.ownerOf(tokenId), employee1);
        assertEq(esopToken.balanceOf(employee1), 0);

        // 2. Before cliff: nothing exercisable
        vm.warp(grantStart + 200 days);
        assertEq(optionNFT.getExercisableOptions(tokenId), 0);

        // 3. At cliff: 25% vested
        vm.warp(grantStart + DEFAULT_CLIFF);
        assertEq(optionNFT.getVestedOptions(tokenId), 2500);

        // 4. Exercise at cliff
        _approveAndExercise(employee1, tokenId, 2500);
        assertEq(esopToken.balanceOf(employee1), 2500 * 1e18);

        // 5. Continue vesting to full
        vm.warp(grantStart + DEFAULT_VESTING);
        uint128 remaining = optionNFT.getExercisableOptions(tokenId);
        assertEq(remaining, 7500);

        // 6. Exercise remaining
        _approveAndExercise(employee1, tokenId, 7500);
        assertEq(esopToken.balanceOf(employee1), uint256(DEFAULT_OPTIONS) * 1e18);

        // 7. Fully exercised
        assertTrue(optionNFT.isGrantFullyExercised(tokenId));

        // 8. Burn
        vm.prank(employee1);
        optionNFT.burnGrant(tokenId);
    }

    function test_E2E_TerminationAndPartialExercise() public {
        // 1. Grant
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;

        // 2. Work for 2 years
        vm.warp(grantStart + 730 days); // 50% = 5000 vested

        // 3. Exercise some before termination
        _approveAndExercise(employee1, tokenId, 2000);

        // 4. Terminate
        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // 5. Exercisable = vested(5000) - exercised(2000) = 3000
        assertEq(optionNFT.getExercisableOptions(tokenId), 3000);

        // 6. Exercise remaining vested within window
        vm.warp(block.timestamp + 45 days);
        _approveAndExercise(employee1, tokenId, 3000);

        assertEq(esopToken.balanceOf(employee1), 5000 * 1e18);

        // 7. Nothing more to exercise
        assertEq(optionNFT.getExercisableOptions(tokenId), 0);

        // 8. Can burn (all vested exercised)
        vm.prank(employee1);
        optionNFT.burnGrant(tokenId);
    }

    function test_E2E_WalletRecoveryPreservesGrant() public {
        // 1. Grant and partially exercise
        uint256 tokenId = _createDefaultGrant(employee1);
        _warpToCliff();
        _approveAndExercise(employee1, tokenId, 1000);

        // 2. Wallet recovery
        address newWallet = makeAddr("newWallet");
        vm.prank(admin);
        optionNFT.approveTransfer(tokenId, newWallet);

        vm.prank(employee1);
        optionNFT.executeApprovedTransfer(tokenId);

        assertEq(optionNFT.ownerOf(tokenId), newWallet);

        // 3. Grant data preserved
        IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
        assertEq(grant.exercisedOptions, 1000);
        assertEq(grant.totalOptions, DEFAULT_OPTIONS);

        // 4. New wallet can continue exercising
        _warpToFullVesting();
        uint128 exercisable = optionNFT.getExercisableOptions(tokenId);
        assertEq(exercisable, 9000); // 10000 - 1000

        // Fund new wallet and exercise
        usdc.mint(newWallet, 1_000_000 * 1e6);
        uint256 cost = optionNFT.getExerciseCost(tokenId, exercisable);
        vm.startPrank(newWallet);
        usdc.approve(address(optionNFT), cost);
        optionNFT.exercise(tokenId, exercisable);
        vm.stopPrank();

        assertEq(esopToken.balanceOf(newWallet), uint256(exercisable) * 1e18);
    }

    function test_E2E_MultipleEmployeesMultipleGrants() public {
        // Employee 1: two grants
        uint256 id1a = _createDefaultGrant(employee1);
        uint256 id1b = _createDefaultGrant(employee1);

        // Employee 2: one grant
        uint256 id2 = _createDefaultGrant(employee2);

        assertEq(optionNFT.balanceOf(employee1), 2);
        assertEq(optionNFT.balanceOf(employee2), 1);

        _warpToFullVesting();

        // Exercise each
        _approveAndExercise(employee1, id1a, DEFAULT_OPTIONS);
        _approveAndExercise(employee1, id1b, DEFAULT_OPTIONS);
        _approveAndExercise(employee2, id2, DEFAULT_OPTIONS);

        assertEq(esopToken.balanceOf(employee1), uint256(DEFAULT_OPTIONS) * 2 * 1e18);
        assertEq(esopToken.balanceOf(employee2), uint256(DEFAULT_OPTIONS) * 1e18);
    }

    function test_E2E_CapEnforcedAcrossMultipleExercises() public {
        // Create a token with small cap
        vm.startPrank(admin);
        // Redeploy with small cap for this test
        vm.stopPrank();

        // Use the existing setup -- MAX_SUPPLY = 1_000_000 tokens
        // Create enough grants to potentially exceed cap
        // Each grant = 10_000 options = 10_000 tokens
        // 100 grants = 1_000_000 tokens = exactly at cap

        // Create 100 grants
        address[] memory employees = new address[](100);
        uint256[] memory tokenIds = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            employees[i] = makeAddr(string(abi.encodePacked("emp", i)));
            usdc.mint(employees[i], 100_000 * 1e6);
            tokenIds[i] = _createDefaultGrant(employees[i]);
        }

        _warpToFullVesting();

        // Exercise all -- should work up to cap
        for (uint256 i = 0; i < 100; i++) {
            uint256 cost = optionNFT.getExerciseCost(tokenIds[i], DEFAULT_OPTIONS);
            vm.startPrank(employees[i]);
            usdc.approve(address(optionNFT), cost);
            optionNFT.exercise(tokenIds[i], DEFAULT_OPTIONS);
            vm.stopPrank();
        }

        assertEq(esopToken.totalSupply(), MAX_SUPPLY);

        // One more grant + exercise should fail at mint
        address extraEmployee = makeAddr("extra");
        usdc.mint(extraEmployee, 100_000 * 1e6);
        uint256 extraId = _createDefaultGrant(extraEmployee);

        uint256 cost = optionNFT.getExerciseCost(extraId, 1);
        vm.startPrank(extraEmployee);
        usdc.approve(address(optionNFT), cost);
        vm.expectRevert(); // ERC20ExceededCap
        optionNFT.exercise(extraId, 1);
        vm.stopPrank();
    }

    function test_E2E_TerminationBeforeCliff_NoExercise() public {
        uint256 tokenId = _createDefaultGrant(employee1);
        uint256 grantStart = block.timestamp;

        // Terminate before cliff
        vm.warp(grantStart + 100 days);
        vm.prank(admin);
        optionNFT.terminateGrant(tokenId);

        // Exercisable should be 0
        assertEq(optionNFT.getExercisableOptions(tokenId), 0);

        // Wait for window to close, then burn
        vm.warp(block.timestamp + DEFAULT_POST_TERM_WINDOW + 1);
        assertTrue(optionNFT.isGrantExpired(tokenId));

        vm.prank(employee1);
        optionNFT.burnGrant(tokenId);
    }
}
