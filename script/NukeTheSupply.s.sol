// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {NukeTheSupply} from "../src/NukeTheSupply.sol";

contract CounterScript is Script {
    NukeTheSupply public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address OWNER = vm.envAddress("OWNER");
        address WETH = vm.envAddress("WETH");
        address UNISWAP_SWAP_ROUTER = vm.envAddress("UNISWAP_SWAP_ROUTER");

        NukeTheSupply NTS = new NukeTheSupply(OWNER, WETH, UNISWAP_SWAP_ROUTER);
        console.log("NukeTheSupply deployed to:", address(NTS));

        vm.stopBroadcast();
    }
}
