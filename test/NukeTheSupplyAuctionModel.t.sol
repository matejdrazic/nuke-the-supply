// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/NukeTheSupplyAuctionModel.sol";
import "../src/WeaponsMarket.sol";

contract NukeTheSupplyTest is Test {
    NukeTheSupply public nts;
    WeaponsMarket public wm;
    ICBMToken public icbm;
    WarheadToken public wh;

    address owner = address(this);
    address user = address(0xBEEF);

    function setUp() public {
        nts = new NukeTheSupply(owner);
        icbm = ICBMToken(nts.getICBMTokenAddress());
        wh = WarheadToken(nts.getWarheadTokenAddress());
        wm = WeaponsMarket(nts.getWeaponsMarket());

        // Fast forward to operations phase
        vm.warp(block.timestamp + 48 hours);
    }

    function testSellTransfersToWeaponsMarket() public {
        uint256 initialWMICBM = icbm.balanceOf(address(wm));

        // Sell day 1
        nts.sell();

        uint256 expectedAmount = nts.getDailySell();
        uint256 newWMICBM = icbm.balanceOf(address(wm));

        assertEq(newWMICBM - initialWMICBM, expectedAmount, "ICBM not transferred correctly");
    }

    function testAuctionLifecycle() public {
        // Simulate sell first
        nts.sell();

        // Advance time to after operations
        vm.warp(block.timestamp + 100 days + 1);

        // Set auction quantity (only once)
        vm.prank(owner);
        wm.setAuctionQuantity();
        uint256 auctionQty = wm.auctionQuantity();
        assertGt(auctionQty, 0, "Auction quantity should be > 0");

        // Give user WH to bid
        uint256 bidAmount = 1000 ether;
        wh.transfer(user, bidAmount);
        
        vm.prank(user);
        wh.approve(address(wm), bidAmount);

        // Start auction
        vm.prank(user);
        wm.startAuction(bidAmount);

        // Confirm bid stored
        assertEq(wm.highestBid(), bidAmount);
        assertEq(wm.highestBidder(), user);

        // Advance time to end auction
        vm.warp(block.timestamp + 25 hours);

        // End auction
        vm.prank(user);
        wm.endAuction();

        // Ensure tokens were transferred and burned
        assertEq(icbm.balanceOf(user), auctionQty, "User did not receive ICBM");
        assertEq(wh.balanceOf(address(wm)), 0, "Warhead not burned");
    }
}
