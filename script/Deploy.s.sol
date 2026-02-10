// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ESOPToken} from "../src/ESOPToken.sol";
import {ESOPOptionNFT} from "../src/ESOPOptionNFT.sol";

contract DeployScript is Script {
    function run() external {
        // Configuration -- override via environment variables
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 maxSupply = vm.envOr("MAX_SUPPLY", uint256(10_000_000 * 1e18)); // 10M tokens default

        vm.startBroadcast();

        // 1. Deploy ESOPToken
        ESOPToken esopToken = new ESOPToken("ESOP Token", "ESOP", maxSupply, admin);
        console.log("ESOPToken deployed at:", address(esopToken));

        // 2. Deploy ESOPOptionNFT
        ESOPOptionNFT optionNFT =
            new ESOPOptionNFT("ESOP Options", "EOPT", address(esopToken), usdcAddress, treasury, admin);
        console.log("ESOPOptionNFT deployed at:", address(optionNFT));

        // 3. Grant MINTER_ROLE to optionNFT
        esopToken.grantRole(esopToken.MINTER_ROLE(), address(optionNFT));
        console.log("MINTER_ROLE granted to ESOPOptionNFT");

        vm.stopBroadcast();

        console.log("Deployment complete. Admin:", admin);
        console.log("Next steps:");
        console.log("  1. Verify contracts on Etherscan");
        console.log("  2. Grant GRANTOR_ROLE to HR operator via multi-sig");
    }
}
