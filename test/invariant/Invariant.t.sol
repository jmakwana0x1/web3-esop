// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ESOPToken} from "../../src/ESOPToken.sol";
import {ESOPOptionNFT} from "../../src/ESOPOptionNFT.sol";
import {IESOPOptionNFT} from "../../src/interfaces/IESOPOptionNFT.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is Test {
    ESOPToken internal esopToken;
    ESOPOptionNFT internal optionNFT;
    MockERC20 internal usdc;
    Handler internal handler;

    address internal admin = makeAddr("admin");
    address internal grantor = makeAddr("grantor");
    address internal treasury = makeAddr("treasury");

    uint256 internal constant MAX_SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);

        vm.startPrank(admin);
        esopToken = new ESOPToken("ESOP Token", "ESOP", MAX_SUPPLY, admin);
        optionNFT = new ESOPOptionNFT("ESOP Options", "EOPT", address(esopToken), address(usdc), treasury, admin);
        esopToken.grantRole(esopToken.MINTER_ROLE(), address(optionNFT));
        optionNFT.grantRole(optionNFT.GRANTOR_ROLE(), grantor);
        vm.stopPrank();

        handler = new Handler(esopToken, optionNFT, usdc, admin, grantor, treasury);

        targetContract(address(handler));
    }

    /// @dev Total minted tokens must never exceed the cap.
    function invariant_TotalMintedTokensNeverExceedsCap() public view {
        assertLe(esopToken.totalSupply(), esopToken.cap());
    }

    /// @dev For every granted token, exercised must never exceed total options.
    function invariant_ExercisedNeverExceedsTotalOptions() public view {
        uint256 length = handler.getGrantedTokenIdsLength();
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = handler.grantedTokenIds(i);
            try optionNFT.getGrant(tokenId) returns (IESOPOptionNFT.OptionGrant memory grant) {
                assertLe(grant.exercisedOptions, grant.totalOptions);
            } catch {
                // Token may have been burned
            }
        }
    }

    /// @dev For every granted token, vested must never exceed total options.
    function invariant_VestedNeverExceedsTotal() public view {
        uint256 length = handler.getGrantedTokenIdsLength();
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = handler.grantedTokenIds(i);
            try optionNFT.getVestedOptions(tokenId) returns (uint128 vested) {
                IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
                assertLe(vested, grant.totalOptions);
            } catch {
                // Token may have been burned
            }
        }
    }

    /// @dev For every granted token, exercised must never exceed vested.
    function invariant_ExercisedNeverExceedsVested() public view {
        uint256 length = handler.getGrantedTokenIdsLength();
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = handler.grantedTokenIds(i);
            try optionNFT.getVestedOptions(tokenId) returns (uint128 vested) {
                IESOPOptionNFT.OptionGrant memory grant = optionNFT.getGrant(tokenId);
                assertLe(grant.exercisedOptions, vested);
            } catch {
                // Token may have been burned
            }
        }
    }
}
