// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-MA-1
 *
 * This test demonstrates the vulnerability of using block.timestamp for time-sensitive operations in an auction.
 *
 * VULNERABILITY EXPLANATION:
 * 1. Miners can manipulate block.timestamp by several seconds (typically up to 900 seconds/15 minutes)
 * 2. In high-value auctions, a miner could slightly advance the timestamp to prematurely end an auction
 * 3. Critical financial decisions (where a second matters) should not rely on block.timestamp precision
 */
contract Auction {
    uint public auctionEndTime;
    address public highestBidder;
    uint public highestBid;
    mapping(address => uint) public pendingReturns;
    bool public ended;

    event BidPlaced(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    constructor(uint _duration) {
        auctionEndTime = block.timestamp + _duration; // Vulnerability!
    }

    function isAuctionEnded() public view returns (bool) {
        return block.timestamp >= auctionEndTime; // Vulnerable comparison!
    }

    function bid() public payable {
        require(!isAuctionEnded(), "Auction has ended");
        require(msg.value > highestBid, "Bid not high enough");

        if (highestBid > 0) {
            pendingReturns[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        emit BidPlaced(msg.sender, msg.value);
    }

    function endAuction() public {
        require(!ended, "Auction already ended");
        require(isAuctionEnded(), "Auction not yet ended");

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);
    }

    function withdraw() public returns (bool) {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;

            // Use call instead of transfer for better compatibility
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "Transfer failed");
        }
        return true;
    }
}

contract AuctionTest is Test {
    Auction public auction;
    uint256 initialDuration = 1 days;
    address bidder1 = address(0x1);
    address bidder2 = address(0x2);
    address minerBidder = address(0x3);

    function setUp() public {
        auction = new Auction(initialDuration);
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
        vm.deal(minerBidder, 10 ether);
    }

    function testRealisticTimestampManipulation() public {
        // Bidder1 places initial bid
        vm.prank(bidder1);
        auction.bid{value: 1 ether}();
        assertEq(auction.highestBidder(), bidder1);

        // Fast forward to near the end of auction (just 30 seconds remaining)
        vm.warp(block.timestamp + initialDuration - 30);

        // MinerBidder places bid
        vm.prank(minerBidder);
        auction.bid{value: 1.5 ether}();
        assertEq(auction.highestBidder(), minerBidder);

        // Bidder2 attempts to place a last-second bid,
        // but miner manipulates timestamp by just 31 seconds
        // NOTE: This is a realistic manipulation that could occur in practice
        vm.warp(block.timestamp + 31); // Just enough to end the auction

        // Bidder2's transaction fails because the miner-manipulated
        // timestamp has passed the auction end time
        vm.prank(bidder2);
        vm.expectRevert("Auction has ended");
        auction.bid{value: 2 ether}();

        // MinerBidder ends auction and wins despite Bidder2's higher bid
        vm.prank(minerBidder);
        auction.endAuction();

        // Verify miner won unfairly by manipulating timestamp
        assertEq(auction.highestBidder(), minerBidder);
        assertEq(auction.highestBid(), 1.5 ether);
    }

}