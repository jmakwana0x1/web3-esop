// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IESOPToken {
    /// @notice Mints tokens to a recipient. Caller must have MINTER_ROLE.
    /// @param to Recipient address
    /// @param amount Number of tokens to mint (18 decimals)
    function mint(address to, uint256 amount) external;

    /// @notice Returns the maximum supply cap.
    function cap() external view returns (uint256);
}
