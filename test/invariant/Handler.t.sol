// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ESOPToken} from "../../src/ESOPToken.sol";
import {ESOPOptionNFT} from "../../src/ESOPOptionNFT.sol";
import {IESOPOptionNFT} from "../../src/interfaces/IESOPOptionNFT.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract Handler is Test {
    ESOPToken public esopToken;
    ESOPOptionNFT public optionNFT;
    MockERC20 public usdc;

    address public admin;
    address public grantor;
    address public treasury;

    uint256[] public grantedTokenIds;
    mapping(uint256 => address) public tokenHolders;

    uint256 public totalOptionsGranted;
    uint256 public totalOptionsExercised;

    constructor(ESOPToken _esopToken, ESOPOptionNFT _optionNFT, MockERC20 _usdc, address _admin, address _grantor, address _treasury) {
        esopToken = _esopToken;
        optionNFT = _optionNFT;
        usdc = _usdc;
        admin = _admin;
        grantor = _grantor;
        treasury = _treasury;
    }

    function grantOptions(uint256 employeeSeed, uint128 totalOptions, uint128 strikePrice) external {
        // Bound inputs to reasonable ranges
        totalOptions = uint128(bound(totalOptions, 1, 100_000));
        strikePrice = uint128(bound(strikePrice, 1, 100_000_000)); // Up to $100

        address employee = makeAddr(string(abi.encodePacked("fuzzEmp", employeeSeed % 10)));

        vm.prank(grantor);
        try optionNFT.grantOptions(
            employee,
            totalOptions,
            strikePrice,
            uint64(block.timestamp),
            365 days,
            1460 days,
            90 days
        ) returns (uint256 tokenId) {
            grantedTokenIds.push(tokenId);
            tokenHolders[tokenId] = employee;
            totalOptionsGranted += totalOptions;
        } catch {}
    }

    function exercise(uint256 tokenIdIndex, uint128 amount) external {
        if (grantedTokenIds.length == 0) return;
        uint256 tokenId = grantedTokenIds[tokenIdIndex % grantedTokenIds.length];
        address holder = tokenHolders[tokenId];
        if (holder == address(0)) return;

        // Check exercisable
        try optionNFT.getExercisableOptions(tokenId) returns (uint128 exercisable) {
            if (exercisable == 0) return;
            amount = uint128(bound(amount, 1, exercisable));

            uint256 cost = optionNFT.getExerciseCost(tokenId, amount);
            usdc.mint(holder, cost);

            vm.startPrank(holder);
            usdc.approve(address(optionNFT), cost);
            try optionNFT.exercise(tokenId, amount) {
                totalOptionsExercised += amount;
            } catch {}
            vm.stopPrank();
        } catch {}
    }

    function terminateGrant(uint256 tokenIdIndex) external {
        if (grantedTokenIds.length == 0) return;
        uint256 tokenId = grantedTokenIds[tokenIdIndex % grantedTokenIds.length];

        vm.prank(admin);
        try optionNFT.terminateGrant(tokenId) {} catch {}
    }

    function warpForward(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 365 days);
        vm.warp(block.timestamp + seconds_);
    }

    function getGrantedTokenIdsLength() external view returns (uint256) {
        return grantedTokenIds.length;
    }
}
