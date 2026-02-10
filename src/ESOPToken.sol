// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ESOPToken
/// @notice ERC20 token with a supply cap. Tokens are only minted when options are exercised.
/// @dev MINTER_ROLE is granted to the ESOPOptionNFT contract after deployment.
contract ESOPToken is ERC20, ERC20Capped, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @param name Token name
    /// @param symbol Token symbol
    /// @param maxSupply Maximum supply cap (18 decimals)
    /// @param admin Admin address (expected to be a multi-sig)
    constructor(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        address admin
    ) ERC20(name, symbol) ERC20Capped(maxSupply) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mints tokens to a recipient. Reverts if cap is exceeded.
    /// @param to Recipient address
    /// @param amount Number of tokens to mint
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @dev Required override to resolve ERC20 and ERC20Capped _update conflict.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }

    /// @dev Required override to resolve ERC165 conflict.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
