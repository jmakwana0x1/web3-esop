// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library VestingMath {
    /// @notice Calculates vested options at a given timestamp.
    /// @param totalOptions Total options in the grant
    /// @param vestingStart Start timestamp of vesting
    /// @param cliffDuration Cliff period in seconds
    /// @param vestingDuration Total vesting duration in seconds (includes cliff)
    /// @param timestamp Evaluation timestamp
    /// @return vested Number of options vested
    function calculateVested(
        uint128 totalOptions,
        uint64 vestingStart,
        uint64 cliffDuration,
        uint64 vestingDuration,
        uint64 timestamp
    ) internal pure returns (uint128 vested) {
        // Before vesting start: nothing vested
        if (timestamp < vestingStart) {
            return 0;
        }

        uint64 elapsed = timestamp - vestingStart;

        // Before cliff: nothing vested
        if (elapsed < cliffDuration) {
            return 0;
        }

        // After full vesting: everything vested
        if (elapsed >= vestingDuration) {
            return totalOptions;
        }

        // Linear vesting: uint256 intermediate to prevent overflow
        vested = uint128((uint256(totalOptions) * uint256(elapsed)) / uint256(vestingDuration));
    }

    /// @notice Calculates exercisable options (vested minus already exercised).
    /// @param vested Total vested options
    /// @param exercised Already exercised options
    /// @return exercisable Options available to exercise
    function calculateExercisable(uint128 vested, uint128 exercised) internal pure returns (uint128 exercisable) {
        if (vested <= exercised) {
            return 0;
        }
        exercisable = vested - exercised;
    }

    /// @notice Calculates USDC cost for exercising options.
    /// @param optionsToExercise Number of options to exercise
    /// @param strikePrice Price per option in USDC (6 decimals)
    /// @return cost Total USDC cost
    function calculateExerciseCost(
        uint128 optionsToExercise,
        uint128 strikePrice
    ) internal pure returns (uint256 cost) {
        cost = uint256(optionsToExercise) * uint256(strikePrice);
    }
}
