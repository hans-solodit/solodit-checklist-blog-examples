pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-GA-1
 *
 * This test demonstrates a Griefing Attack on a timed withdrawal mechanism.
 * A malicious actor repeatedly deposits small amounts to a victim's address,
 * resetting their `lastDeposit` timestamp and preventing them from ever withdrawing their funds.
 *
 * The vulnerability is that anyone can update anyone else's last deposit timestamp,
 * which allows attackers to grief legitimate users by constantly resetting their withdrawal timer.
 */
contract GriefingAttackTest is Test {
    VulnerableVault public vault;
    address public alice = address(1);
    address public attacker = address(2);

    function setUp() public {
        vault = new VulnerableVault();
        vm.deal(alice, 1 ether);
        vm.deal(attacker, 0.1 ether);
    }

    function testGriefingAttack() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit{value: 1 ether}(alice);

        // Time almost passes
        vm.warp(block.timestamp + 3 minutes);

        // Attacker resets Alice's timer
        vm.prank(attacker);
        vault.deposit{value: 1 wei}(alice);

        // Alice tries to withdraw but fails
        vm.prank(alice);
        vm.expectRevert("Wait period not over");
        vault.withdraw(1 ether);
    }
}

contract VulnerableVault {
    uint256 public delay = 3 minutes;
    mapping(address => uint256) public lastDeposit;
    mapping(address => uint256) public balances;

    function deposit(address _for) public payable {
        lastDeposit[_for] = block.timestamp;
        balances[_for] += msg.value;
    }

    function withdraw(uint256 _amount) public {
        require(block.timestamp >= lastDeposit[msg.sender] + delay, "Wait period not over");
        require(balances[msg.sender] >= _amount, "Insufficient funds");
        balances[msg.sender] -= _amount;
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");    }
}
