// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/WeaponsMarket.sol";
import "../src/WarheadToken.sol"; // Only if needed
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock INukeTheSupply
contract MockNukeTheSupply is INukeTheSupply {
    bool public override isOperationsPhaseEnded = true;

    function setPhaseEnded(bool ended) external {
        isOperationsPhaseEnded = ended;
    }
}

// Simple mock ERC20 for ICBM and Warhead
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract WeaponsMarketTest is Test {
    WeaponsMarket public market;
    MockERC20 public icbm;
    WarheadToken public warhead;
    MockNukeTheSupply public nuke;

    address alice = address(1);
    address bob = address(2);

    address warheadOwner = address(3);

    uint256 public constant WARHEAD_SUPPLY = 25_000_000 ether;

    function setUp() public {
        icbm = new MockERC20("ICBM", "ICBM");
        warhead = new WarheadToken("Warhead", "WAR", WARHEAD_SUPPLY, address(this));
        nuke = new MockNukeTheSupply();

        market = new WeaponsMarket(address(icbm), address(warhead), address(nuke), address(this));

        icbm.mint(address(market), 10000 ether);
        warhead.mint(alice, 1000 ether);
        warhead.mint(bob, 1000 ether);

        vm.prank(alice);
        warhead.approve(address(market), type(uint256).max);

        vm.prank(bob);
        warhead.approve(address(market), type(uint256).max);
    }

    function testSetAuctionQuantity() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();
        assertEq(market.auctionQuantity(), 100 ether); // 1% of 10,000 ether
    }

    function testStartAuction() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        assertEq(market.highestBidder(), alice);
        assertEq(market.highestBid(), 50 ether);
    }

    function testBidHigher() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.prank(bob);
        market.bid(60 ether);

        assertEq(market.highestBidder(), bob);
        assertEq(market.highestBid(), 60 ether);
    }

    function testWithdrawBid() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.prank(bob);
        market.bid(60 ether);

        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        market.withdrawBid();

        assertEq(warhead.balanceOf(alice), 1000 ether); // Alice gets her bid back
    }

    function testEndAuction() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        market.endAuction();

        assertEq(icbm.balanceOf(alice), 100 ether);
        assertEq(warhead.totalSupply(), WARHEAD_SUPPLY + 2000 ether - 50 ether); // Burned
    }

    function testRevertStartAuctionBeforeQuantitySet() public {
        vm.expectRevert("Auction quantity not set");
        vm.prank(alice);
        market.startAuction(50 ether);
    }

    function testRevertStartAuctionAlreadyStarted() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.expectRevert("Auction already started");
        vm.prank(bob);
        market.startAuction(60 ether);
    }

    function testRevertLowerBid() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.expectRevert("Bid not higher than current highest");
        vm.prank(bob);
        market.bid(30 ether);
    }

    function testRevertWithdrawAsHighestBidderDuringAuction() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.expectRevert("Highest bidder cannot withdraw during auction");
        vm.prank(alice);
        market.withdrawBid();
    }

    function testRevertWithdrawWithNoBid() public {
        vm.expectRevert("No bid to withdraw");
        vm.prank(alice);
        market.withdrawBid();
    }

    function testRevertEndAuctionTooEarly() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.expectRevert("Auction not ended");
        vm.prank(alice);
        market.endAuction();
    }

    function testRevertEndAuctionTwice() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        market.endAuction();

        vm.expectRevert("Auction not started");
        vm.prank(alice);
        market.endAuction();
    }

    function testRestartAuctionAfterEnd() public {
        vm.prank(market.owner());
        market.setAuctionQuantity();

        vm.prank(alice);
        market.startAuction(50 ether);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        market.endAuction();

        vm.prank(bob);
        market.startAuction(60 ether);

        assertEq(market.highestBidder(), bob);
    }

}
