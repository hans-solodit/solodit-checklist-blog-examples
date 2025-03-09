pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Overview:
// Checklist Item ID: SOL-AM-DOSA-1

// This test demonstrates a denial-of-service (DoS) vulnerability in a contract's ETH withdrawal function.
// The vulnerability occurs when the contract directly transfers fees to the owner before allowing the user to withdraw.
// If the owner's address is set to a contract that reverts on ETH receive, user withdrawals will fail.
// The test will show that a normal user is unable to withdraw funds because owner's contract reverts on ETH transfer.

// Contract that reverts when receiving ETH
contract RevertingReceiver {
    // Explicitly revert on ETH receive
    receive() external payable {
        revert("Reverting ETH Receiver");
    }

    // Fallback also reverts
    fallback() external payable {
        revert("Reverting ETH Receiver");
    }
}

// Vulnerable contract that transfers fees to owner before user withdrawal
contract VulnerableETHWithdrawal is Ownable {
    mapping(address => uint256) public balances;

    constructor() Ownable(msg.sender) {}

    // Allow users to deposit ETH
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    // Vulnerable withdrawal function
    function withdraw(uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // Subtract the withdrawn amount from user's balance
        balances[msg.sender] -= amount;

        // Calculate fee
        uint256 fee = amount / 10; // 10% fee
        uint256 userAmount = amount - fee;

        // Transfer fee to owner before user withdrawal - VULNERABLE LINE
        (bool feeSuccess, ) = owner().call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");

        // Transfer remaining amount to user
        (bool success, ) = msg.sender.call{value: userAmount}("");
        require(success, "User transfer failed");
    }

    // Get contract balance
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}

contract VulnerableETHWithdrawalTest is Test {
    VulnerableETHWithdrawal public vulnerableContract;
    RevertingReceiver public revertingContract;
    address public user = address(1);

    function setUp() public {
        vulnerableContract = new VulnerableETHWithdrawal();
        revertingContract = new RevertingReceiver();
        vm.deal(user, 10 ether);

        // Set the user's balance in the contract
        vm.startPrank(user);
        vulnerableContract.deposit{value: 10 ether}();
        vm.stopPrank();

        // Set the owner to the reverting contract address
        vulnerableContract.transferOwnership(address(revertingContract));
    }

    function testWithdrawalFailsDueToRevertingOwner() public {
        vm.startPrank(user);
        // Ensure user has a balance
        assertEq(vulnerableContract.balances(user), 10 ether);

        // Attempt to withdraw funds - should fail because the owner (reverting contract) rejects ETH
        vm.expectRevert("Fee transfer failed");
        vulnerableContract.withdraw(5 ether);

        // Verify balance remains unchanged
        assertEq(vulnerableContract.balances(user), 10 ether);
        vm.stopPrank();
    }

    // Helper to make the test contract able to receive ETH
    receive() external payable {}
}
