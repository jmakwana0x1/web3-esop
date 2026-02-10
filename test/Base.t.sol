// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ESOPToken} from "../src/ESOPToken.sol";
import {ESOPOptionNFT} from "../src/ESOPOptionNFT.sol";
import {IESOPOptionNFT} from "../src/interfaces/IESOPOptionNFT.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

abstract contract BaseTest is Test {
    ESOPToken internal esopToken;
    ESOPOptionNFT internal optionNFT;
    MockERC20 internal usdc;

    address internal admin = makeAddr("admin");
    address internal grantor = makeAddr("grantor");
    address internal employee1 = makeAddr("employee1");
    address internal employee2 = makeAddr("employee2");
    address internal treasury = makeAddr("treasury");

    uint128 internal constant DEFAULT_OPTIONS = 10_000;
    uint128 internal constant DEFAULT_STRIKE = 1_000_000; // $1.00 in USDC (6 decimals)
    uint64 internal constant DEFAULT_CLIFF = 365 days;
    uint64 internal constant DEFAULT_VESTING = 1460 days; // 4 years
    uint64 internal constant DEFAULT_POST_TERM_WINDOW = 90 days;
    uint256 internal constant MAX_SUPPLY = 1_000_000 * 1e18;

    function setUp() public virtual {
        // Deploy mock USDC
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy contracts and configure roles as admin
        vm.startPrank(admin);

        esopToken = new ESOPToken("ESOP Token", "ESOP", MAX_SUPPLY, admin);
        optionNFT = new ESOPOptionNFT("ESOP Options", "EOPT", address(esopToken), address(usdc), treasury, admin);
        esopToken.grantRole(esopToken.MINTER_ROLE(), address(optionNFT));
        optionNFT.grantRole(optionNFT.GRANTOR_ROLE(), grantor);

        vm.stopPrank();

        // Fund employees with USDC
        usdc.mint(employee1, 1_000_000 * 1e6);
        usdc.mint(employee2, 1_000_000 * 1e6);
    }

    function _createDefaultGrant(address employee) internal returns (uint256 tokenId) {
        vm.prank(grantor);
        tokenId = optionNFT.grantOptions(
            employee,
            DEFAULT_OPTIONS,
            DEFAULT_STRIKE,
            uint64(block.timestamp),
            DEFAULT_CLIFF,
            DEFAULT_VESTING,
            DEFAULT_POST_TERM_WINDOW
        );
    }

    function _approveAndExercise(address employee, uint256 tokenId, uint128 amount) internal {
        uint256 cost = optionNFT.getExerciseCost(tokenId, amount);
        vm.startPrank(employee);
        usdc.approve(address(optionNFT), cost);
        optionNFT.exercise(tokenId, amount);
        vm.stopPrank();
    }

    function _warpToCliff() internal {
        vm.warp(block.timestamp + DEFAULT_CLIFF);
    }

    function _warpToFullVesting() internal {
        vm.warp(block.timestamp + DEFAULT_VESTING);
    }
}
