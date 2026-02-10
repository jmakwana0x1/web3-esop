// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VestingMath} from "../src/libraries/VestingMath.sol";

/// @dev Wrapper to expose internal library functions for testing.
contract VestingMathHarness {
    function calculateVested(
        uint128 totalOptions,
        uint64 vestingStart,
        uint64 cliffDuration,
        uint64 vestingDuration,
        uint64 timestamp
    ) external pure returns (uint128) {
        return VestingMath.calculateVested(totalOptions, vestingStart, cliffDuration, vestingDuration, timestamp);
    }

    function calculateExercisable(uint128 vested, uint128 exercised) external pure returns (uint128) {
        return VestingMath.calculateExercisable(vested, exercised);
    }

    function calculateExerciseCost(uint128 optionsToExercise, uint128 strikePrice) external pure returns (uint256) {
        return VestingMath.calculateExerciseCost(optionsToExercise, strikePrice);
    }
}

contract VestingMathTest is Test {
    VestingMathHarness internal harness;

    uint128 internal constant TOTAL = 10_000;
    uint64 internal constant START = 1_000_000;
    uint64 internal constant CLIFF = 365 days;
    uint64 internal constant DURATION = 1460 days; // 4 years

    function setUp() public {
        harness = new VestingMathHarness();
    }

    // ==================== calculateVested ====================

    function test_CalculateVested_BeforeCliff_ReturnsZero() public view {
        uint128 vested = harness.calculateVested(TOTAL, START, CLIFF, DURATION, START + CLIFF - 1);
        assertEq(vested, 0);
    }

    function test_CalculateVested_AtCliffEnd_ReturnsCliffPortion() public view {
        uint128 vested = harness.calculateVested(TOTAL, START, CLIFF, DURATION, START + CLIFF);
        // 365 days elapsed out of 1460 days = 25%
        assertEq(vested, 2500);
    }

    function test_CalculateVested_MidVesting_ReturnsProportional() public view {
        // 2 years in = 50%
        uint128 vested = harness.calculateVested(TOTAL, START, CLIFF, DURATION, START + 730 days);
        assertEq(vested, 5000);
    }

    function test_CalculateVested_AtVestingEnd_ReturnsTotal() public view {
        uint128 vested = harness.calculateVested(TOTAL, START, CLIFF, DURATION, START + DURATION);
        assertEq(vested, TOTAL);
    }

    function test_CalculateVested_AfterVestingEnd_ReturnsTotal() public view {
        uint128 vested = harness.calculateVested(TOTAL, START, CLIFF, DURATION, START + DURATION + 365 days);
        assertEq(vested, TOTAL);
    }

    function test_CalculateVested_ZeroTotalOptions_ReturnsZero() public view {
        uint128 vested = harness.calculateVested(0, START, CLIFF, DURATION, START + DURATION);
        assertEq(vested, 0);
    }

    function test_CalculateVested_CliffEqualToVesting_ReturnsAllAtCliff() public view {
        uint128 vested = harness.calculateVested(TOTAL, START, 365 days, 365 days, START + 365 days);
        assertEq(vested, TOTAL);
    }

    function test_CalculateVested_ZeroCliff_VestsFromStart() public view {
        // 1 year out of 4 years with no cliff
        uint128 vested = harness.calculateVested(TOTAL, START, 0, DURATION, START + 365 days);
        assertEq(vested, 2500);
    }

    function test_CalculateVested_BeforeStart_ReturnsZero() public view {
        uint128 vested = harness.calculateVested(TOTAL, START, CLIFF, DURATION, START - 1);
        assertEq(vested, 0);
    }

    // ==================== calculateExercisable ====================

    function test_CalculateExercisable_NoneExercised_ReturnsAllVested() public view {
        uint128 exercisable = harness.calculateExercisable(5000, 0);
        assertEq(exercisable, 5000);
    }

    function test_CalculateExercisable_PartiallyExercised_ReturnsDifference() public view {
        uint128 exercisable = harness.calculateExercisable(5000, 2000);
        assertEq(exercisable, 3000);
    }

    function test_CalculateExercisable_FullyExercised_ReturnsZero() public view {
        uint128 exercisable = harness.calculateExercisable(5000, 5000);
        assertEq(exercisable, 0);
    }

    function test_CalculateExercisable_VestedLessThanExercised_ReturnsZero() public view {
        // Edge case: shouldn't happen in practice but should handle gracefully
        uint128 exercisable = harness.calculateExercisable(3000, 5000);
        assertEq(exercisable, 0);
    }

    // ==================== calculateExerciseCost ====================

    function test_CalculateExerciseCost_StandardCase() public view {
        // 1000 options * $1.00 (1_000_000 USDC units) = 1_000_000_000 USDC units = $1000
        uint256 cost = harness.calculateExerciseCost(1000, 1_000_000);
        assertEq(cost, 1_000_000_000);
    }

    function test_CalculateExerciseCost_ZeroOptions_ReturnsZero() public view {
        uint256 cost = harness.calculateExerciseCost(0, 1_000_000);
        assertEq(cost, 0);
    }

    function test_CalculateExerciseCost_LargeValues_NoOverflow() public view {
        // Max uint128 values -- should not overflow in uint256
        uint128 maxOpts = type(uint128).max;
        uint128 maxPrice = type(uint128).max;
        uint256 cost = harness.calculateExerciseCost(maxOpts, maxPrice);
        assertEq(cost, uint256(maxOpts) * uint256(maxPrice));
    }

    // ==================== Fuzz Tests ====================

    function testFuzz_CalculateVested_NeverExceedsTotal(
        uint128 total,
        uint64 vestingStart,
        uint64 cliffDuration,
        uint64 vestingDuration,
        uint64 timestamp
    ) public view {
        vm.assume(vestingDuration > 0);
        vm.assume(vestingDuration >= cliffDuration);

        uint128 vested = harness.calculateVested(total, vestingStart, cliffDuration, vestingDuration, timestamp);
        assertLe(vested, total);
    }

    function testFuzz_CalculateVested_MonotonicallyIncreasing(uint64 t1, uint64 t2) public view {
        vm.assume(t1 <= t2);

        uint128 vested1 = harness.calculateVested(TOTAL, START, CLIFF, DURATION, t1);
        uint128 vested2 = harness.calculateVested(TOTAL, START, CLIFF, DURATION, t2);
        assertLe(vested1, vested2);
    }

    function testFuzz_CalculateExerciseCost_Deterministic(uint128 amount, uint128 price) public view {
        uint256 cost = harness.calculateExerciseCost(amount, price);
        assertEq(cost, uint256(amount) * uint256(price));
    }
}
