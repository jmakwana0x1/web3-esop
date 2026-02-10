// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ESOPTokenTest is BaseTest {
    bytes32 internal minterRole;

    function setUp() public override {
        super.setUp();
        minterRole = esopToken.MINTER_ROLE();
    }

    // ==================== Constructor ====================

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(esopToken.name(), "ESOP Token");
        assertEq(esopToken.symbol(), "ESOP");
    }

    function test_Constructor_SetsCap() public view {
        assertEq(esopToken.cap(), MAX_SUPPLY);
    }

    function test_Constructor_GrantsDefaultAdminRole() public view {
        assertTrue(esopToken.hasRole(esopToken.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Constructor_DoesNotGrantMinterRole() public view {
        assertFalse(esopToken.hasRole(minterRole, admin));
    }

    function test_Constructor_ZeroInitialSupply() public view {
        assertEq(esopToken.totalSupply(), 0);
    }

    // ==================== Mint ====================

    function test_Mint_Success_ByMinterRole() public {
        vm.prank(address(optionNFT));
        esopToken.mint(employee1, 1000 * 1e18);
        assertEq(esopToken.balanceOf(employee1), 1000 * 1e18);
    }

    function test_Mint_RevertWhen_CallerLacksMinterRole() public {
        vm.prank(employee1);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, employee1, minterRole)
        );
        esopToken.mint(employee1, 1000 * 1e18);
    }

    function test_Mint_RevertWhen_ExceedsCap() public {
        vm.prank(address(optionNFT));
        vm.expectRevert();
        esopToken.mint(employee1, MAX_SUPPLY + 1);
    }

    function test_Mint_EmitsTransferEvent() public {
        vm.prank(address(optionNFT));
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), employee1, 1000 * 1e18);
        esopToken.mint(employee1, 1000 * 1e18);
    }

    // ==================== Cap ====================

    function test_Cap_ReturnsCorrectValue() public view {
        assertEq(esopToken.cap(), MAX_SUPPLY);
    }

    // ==================== Role Management ====================

    function test_RoleManagement_AdminCanGrantMinterRole() public {
        address newMinter = makeAddr("newMinter");
        vm.prank(admin);
        esopToken.grantRole(minterRole, newMinter);
        assertTrue(esopToken.hasRole(minterRole, newMinter));
    }

    function test_RoleManagement_AdminCanRevokeMinterRole() public {
        vm.prank(admin);
        esopToken.revokeRole(minterRole, address(optionNFT));
        assertFalse(esopToken.hasRole(minterRole, address(optionNFT)));
    }

    function test_RoleManagement_NonAdminCannotGrantRoles() public {
        vm.prank(employee1);
        vm.expectRevert();
        esopToken.grantRole(minterRole, employee1);
    }

    // ==================== Events ====================

    event Transfer(address indexed from, address indexed to, uint256 value);
}
