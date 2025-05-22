// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {NukeTheSupply} from "../src/NukeTheSupply.sol";

contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Replace these with the actual addresses
        address OWNER = address(1);
        address WETH = address(2);
        address UNISWAP_V3_SWAP_ROUTER = address(3);

        NukeTheSupply NTS = new NukeTheSupply(OWNER, WETH, UNISWAP_V3_SWAP_ROUTER);
        console.log("NukeTheSupply deployed to:", address(NTS));

        vm.stopBroadcast();
    }
}
