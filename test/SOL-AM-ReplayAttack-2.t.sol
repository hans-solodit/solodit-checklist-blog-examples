// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-ReplayAttack-2
 *
 * This test demonstrates a replay attack vulnerability across different blockchain networks.
 * The VulnerableVault contract lacks chain-specific data in its signature verification process,
 * making signatures valid on one chain replayable on another.
 * This allows an attacker to execute unauthorized transactions on a different chain
 * using a valid signature from the original chain.
 */

contract VulnerableVault {
    address public owner;
    address public recipient;
    mapping(bytes32 => bool) public isConsumed;

    constructor(address _owner, address _recipient) {
        owner = _owner;
        recipient = _recipient;
    }

    function changeRecipient(address _newRecipient, uint256 _expiry, bytes memory _signature) external {
        require(block.timestamp <= _expiry, "Signature expired");

        // Vulnerability: Missing chain ID in the signature data
        bytes32 messageHash = keccak256(abi.encode(
            msg.sender,
            _newRecipient,
            _expiry
        ));

        // For PoC, use a simple signature check
        bytes32 signedHash = abi.decode(_signature, (bytes32));
        require(signedHash == messageHash, "Invalid signature");
        require(!isConsumed[messageHash], "Signature already used");

        isConsumed[messageHash] = true;
        recipient = _newRecipient;
    }
}

contract ReplayAttackTest is Test {
    VulnerableVault public vault;
    address owner = address(1);
    address recipient = address(2);
    address newRecipient = address(3);
    address maliciousRecipient = address(4);
    uint256 expiry;

    function setUp() public {
        expiry = block.timestamp + 1 hours;
        vault = new VulnerableVault(owner, recipient);
    }

    function testCrossChainReplayAttack() public {
        // 1. Create a signature for Chain A
        bytes32 messageHash = keccak256(abi.encode(
            address(this),
            newRecipient,
            expiry
        ));

        // For PoC, use the hash directly as the signature
        bytes memory signature = abi.encode(messageHash);

        // 2. Execute on "Chain A"
        vm.prank(address(this));
        vault.changeRecipient(newRecipient, expiry, signature);
        assertEq(vault.recipient(), newRecipient);

        // 3. Reset the consumed flag to simulate a different chain
        bytes32 usedHash = keccak256(abi.encode(
            address(this),
            newRecipient,
            expiry
        ));
        vm.store(
            address(vault),
            keccak256(abi.encode(usedHash, uint256(2))), // slot for isConsumed mapping
            bytes32(0)
        );

        // 4. Replay on "Chain B" with the same parameters to simulate cross-chain replay
        vm.prank(address(this));
        vault.changeRecipient(newRecipient, expiry, signature);

        // 5. Verify the attack succeeded on "Chain B"
        assertEq(vault.recipient(), newRecipient, "Replay on Chain B succeeded");
    }
}
