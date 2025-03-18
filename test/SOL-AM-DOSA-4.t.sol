// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-DOSA-4
 *
 * This test demonstrates a Denial-of-Service (DOS) vulnerability in a withdrawal queue system
 * where an attacker can block the entire queue by manipulating their withdrawal status.
 * The vulnerability allows an attacker to enter the withdrawal queue and then reset their status to false
 * while remaining in the queue, preventing any subsequent withdrawals from being processed.
 */

contract WithdrawalQueue {
    struct Withdrawal {
        address user;
        uint256 amount;
    }

    // Queue of withdrawal requests
    Withdrawal[] public withdrawalQueue;

    // Tracks if a user has a pending withdrawal request
    mapping(address => bool) public withdrawalRequested;

    // User balances
    mapping(address => uint256) public balances;

    // Current index in the queue being processed
    uint256 public currentIndex;

    // Add funds to the contract
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    // Request a withdrawal
    function requestWithdrawal(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(!withdrawalRequested[msg.sender], "Withdrawal already requested");

        // Add to queue
        withdrawalQueue.push(Withdrawal({
            user: msg.sender,
            amount: amount
        }));

        // Mark as requested
        withdrawalRequested[msg.sender] = true;
    }

    // VULNERABLE FUNCTION: Can be exploited
    function resetUserStatus() external {
        // Anyone can reset their status while remaining in the queue
        withdrawalRequested[msg.sender] = false;
        // Note: User is not removed from the queue!
    }

    // Process the next withdrawal in the queue
    function processNextWithdrawal() external {
        require(withdrawalQueue.length > currentIndex, "No withdrawals to process");

        // Get the next withdrawal
        Withdrawal memory withdrawal = withdrawalQueue[currentIndex];

        // VULNERABLE: This check can be bypassed by resetting the status
        require(withdrawalRequested[withdrawal.user], "Withdrawal no longer requested");

        // Process the withdrawal
        uint256 amount = withdrawal.amount;
        require(balances[withdrawal.user] >= amount, "Insufficient balance");

        // Update balance
        balances[withdrawal.user] -= amount;

        // Reset withdrawal request
        withdrawalRequested[withdrawal.user] = false;

        // Send funds
        (bool success, ) = payable(withdrawal.user).call{value:amount}("");
        require(success, "Failed to send funds");

        // Move to next in queue
        currentIndex++;
    }

    // Get length of queue
    function getQueueLength() external view returns (uint256) {
        return withdrawalQueue.length;
    }
}

contract WithdrawalQueueTest is Test {
    WithdrawalQueue public queue;
    address public user1;
    address public user2;
    address public attacker;

    function setUp() public {
        queue = new WithdrawalQueue();

        user1 = address(0x1);
        user2 = address(0x2);
        attacker = address(0x3);

        // Fund accounts
        vm.deal(user1, 5 ether);
        vm.deal(user2, 5 ether);
        vm.deal(attacker, 5 ether);

        // Users deposit funds
        vm.prank(user1);
        queue.deposit{value: 2 ether}();

        vm.prank(user2);
        queue.deposit{value: 2 ether}();

        vm.prank(attacker);
        queue.deposit{value: 1 ether}();
    }

    function testDOSAttack() public {
        // User1 requests withdrawal
        vm.prank(user1);
        queue.requestWithdrawal(1 ether);

        // Attacker requests withdrawal
        vm.prank(attacker);
        queue.requestWithdrawal(0.5 ether);

        // User2 requests withdrawal
        vm.prank(user2);
        queue.requestWithdrawal(1 ether);

        // Verify withdrawal queue length
        assertEq(queue.getQueueLength(), 3);

        // Process User1's withdrawal - works fine
        queue.processNextWithdrawal();
        assertEq(queue.currentIndex(), 1);

        // Attacker resets their status while still in queue
        vm.prank(attacker);
        queue.resetUserStatus();

        // Try to process Attacker's withdrawal - will fail
        vm.expectRevert("Withdrawal no longer requested");
        queue.processNextWithdrawal();

        // Stuck at index 1, can't reach user2's withdrawal
        assertEq(queue.currentIndex(), 1);
    }
}