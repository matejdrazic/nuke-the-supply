// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {NukeTheSupply} from "../src/NukeTheSupplyAuctionModel.sol";

/*
SEPOLIA:
forge script --broadcast --rpc-url "https://sepolia.infura.io/v3/fe4293108e014888a9061996b0f2785f" --private-key db1ba5c3de75dfb96e43583fe7dab4bc739c47056c1507d4216e4e6db560825b --verify --etherscan-api-key 9RQ8CFB9AGHM32H5YMYQBWG13FI167GTMM --resume script/NukeTheSupplyAuctionModel.s.sol:NukeTheSupplyScript

PULSECHAIN TESTNET:
forge script --broadcast --rpc-url "https://pulsechain.publicnode.com" --private-key db1ba5c3de75dfb96e43583fe7dab4bc739c47056c1507d4216e4e6db560825b script/NukeTheSupplyAuctionModel.s.sol:NukeTheSupplyScript
forge script --broadcast --rpc-url "https://pulsechain.publicnode.com" --private-key db1ba5c3de75dfb96e43583fe7dab4bc739c47056c1507d4216e4e6db560825b --verify --etherscan-api-key 9RQ8CFB9AGHM32H5YMYQBWG13FI167GTMM --resume script/NukeTheSupplyAuctionModel.s.sol:NukeTheSupplyScript

*/

contract NukeTheSupplyScript is Script {

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Replace these with the actual addresses
        address OWNER = 0x106bB8a051A86db69a2Cb0F68Fb12c0E31fB4066;

        // Owner to put on production deployment: 0x915b4145e169CE7352936E88546AC8667D22723c


        NukeTheSupply NTS = new NukeTheSupply(OWNER);
        console.log("NukeTheSupply deployed to:", address(NTS));

        vm.stopBroadcast();
    }
}
