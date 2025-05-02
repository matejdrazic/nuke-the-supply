// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Imports
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./WarheadToken.sol"; // Import WarheadToken for burn


interface INukeTheSupply {
    function isOperationsPhaseEnded() external view returns (bool);
}

contract WeaponsMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Token addresses
    IERC20 public ICBM;
    IERC20 public Warhead; // Use IERC20 instead of WarheadToken

    // NukeTheSupply contract for operations phase check
    INukeTheSupply public nukeTheSupply;

    // Auction parameters
    uint256 public constant AUCTION_DURATION = 24 hours; // Duration of each auction
    uint256 public auctionQuantity; // Fixed 1% of initial ICBM pool
    bool public auctionQuantitySet; // Flag to ensure quantity is set once
    bool public started; // Whether an auction is active
    bool public ended; // Whether the current auction has ended
    uint256 public endAt; // Timestamp when the current auction ends
    address public highestBidder; // Address of the current highest bidder
    uint256 public highestBid; // Amount of Warhead tokens in the highest bid
    mapping(address => uint256) public bids; // Tracks bids for withdrawal

    // EVENTS
    event AuctionQuantitySet(uint256 quantity);
    event AuctionStarted(address indexed starter, uint256 bid, uint256 endAt);
    event BidPlaced(address indexed bidder, uint256 amount);
    event BidWithdrawn(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 bidAmount, uint256 icbmAmount);

    constructor(address icbm_, address warhead_, address nukeTheSupply_, address owner_) Ownable(owner_) {
        ICBM = IERC20(icbm_);
        Warhead = IERC20(warhead_);
        nukeTheSupply = INukeTheSupply(nukeTheSupply_);
    }

    // Set the fixed auction quantity (1% of initial ICBM pool) after operations phase
    function setAuctionQuantity() external onlyOwner {
        require(!auctionQuantitySet, "Quantity already set");
        require(nukeTheSupply.isOperationsPhaseEnded(), "Operations phase not ended");
        uint256 totalICBM = ICBM.balanceOf(address(this));
        require(totalICBM > 0, "No ICBM tokens in pool");
        auctionQuantity = totalICBM / 100; // 1% of the pool
        auctionQuantitySet = true;
        emit AuctionQuantitySet(auctionQuantity);
    }

    // Start a new auction with an initial bid
    function startAuction(uint256 bidAmount) external {
        require(auctionQuantitySet, "Auction quantity not set");
        require(!started, "Auction already started");
        require(nukeTheSupply.isOperationsPhaseEnded(), "Operations phase not ended");
        require(ICBM.balanceOf(address(this)) >= auctionQuantity, "Insufficient ICBM tokens");
        require(bidAmount > 0, "Bid must be greater than 0");
        require(Warhead.allowance(_msgSender(), address(this)) >= bidAmount, "Insufficient Warhead allowance");

        // Reset auction ended flag
        ended = false;

        // Transfer Warhead tokens to the contract
        Warhead.safeTransferFrom(_msgSender(), address(this), bidAmount);

        started = true;
        endAt = block.timestamp + AUCTION_DURATION;
        highestBidder = _msgSender();
        highestBid = bidAmount;
        bids[_msgSender()] = bidAmount;

        emit AuctionStarted(_msgSender(), bidAmount, endAt);
    }

    // Place a higher bid
    function bid(uint256 bidAmount) external {
        require(started, "Auction not started");
        require(block.timestamp < endAt, "Auction ended");
        require(bidAmount > highestBid, "Bid not higher than current highest");
        require(Warhead.allowance(_msgSender(), address(this)) >= bidAmount, "Insufficient Warhead allowance");

        // Store previous highest bid for withdrawal
        if (highestBidder != address(0)) {
            bids[highestBidder] = highestBid;
        }

        // Transfer Warhead tokens to the contract
        Warhead.safeTransferFrom(_msgSender(), address(this), bidAmount);

        highestBidder = _msgSender();
        highestBid = bidAmount;
        bids[_msgSender()] = bidAmount;

        emit BidPlaced(_msgSender(), bidAmount);
    }

    // Withdraw non-winning bids
    function withdrawBid() external nonReentrant {
        require(_msgSender() != highestBidder || block.timestamp >= endAt, "Highest bidder cannot withdraw during auction");
        uint256 amount = bids[_msgSender()];
        require(amount > 0, "No bid to withdraw");

        bids[_msgSender()] = 0;
        Warhead.safeTransfer(_msgSender(), amount);

        emit BidWithdrawn(_msgSender(), amount);
    }

    // End the auction and allow the highest bidder to claim ICBM tokens
    function endAuction() external nonReentrant {
        require(started, "Auction not started");
        require(block.timestamp >= endAt, "Auction not ended");
        require(!ended, "Auction already ended");

        ended = true;
        started = false; // Allow new auction to start

        if (highestBidder != address(0)) {
            // Burn the highest bidder's Warhead tokens (already held by the contract)
            WarheadToken(address(Warhead)).burn(highestBid);

            // Transfer ICBM tokens to the highest bidder
            ICBM.safeTransfer(highestBidder, auctionQuantity);

            emit AuctionEnded(highestBidder, highestBid, auctionQuantity);
        } else {
            // No bids: reset for next auction
            emit AuctionEnded(address(0), 0, 0);
        }

        // Reset for next auction
        highestBidder = address(0);
        highestBid = 0;
    }

    // View function to get current ICBM balance
    function getICBMBalance() external view returns (uint256) {
        return ICBM.balanceOf(address(this));
    }

    // View function to get current Warhead balance
    function getWarheadBalance() external view returns (uint256) {
        return Warhead.balanceOf(address(this));
    }
}