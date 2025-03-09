pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Overview:
// Checklist Item ID: SOL-AM-DOSA-2

// This test demonstrates a denial-of-service (DoS) vulnerability where an attacker can clog the contract with numerous zero-value transactions,
// making subsequent legitimate operations expensive or impossible by targeting the lack of a minimum transaction amount enforced. The test
// exploits the `VulnerableContract` by submitting a large number of zero-value withdrawal requests, then attempts a legitimate withdrawal
// to show the increased gas cost and potential for denial of service.

contract VulnerableContract {
    struct WithdrawalRequest {
        address payable recipient;
        uint256 amount;
    }

    WithdrawalRequest[] public withdrawals;

    function requestWithdrawal(uint256 _amount) external {
        WithdrawalRequest memory request = WithdrawalRequest(payable(msg.sender), _amount);
        withdrawals.push(request);
    }

    function processWithdrawals(uint256 _count) external {
        for (uint256 i = 0; i < _count; i++) {
            WithdrawalRequest memory request = withdrawals[i];
            request.recipient.transfer(request.amount); // Vulnerable Line: No minimum amount check.
        }
    }
}

contract VulnerableContractTest is Test {
    VulnerableContract public vulnerableContract;
    address payable attacker = payable(address(1337));
    address payable user = payable(address(42));

    function setUp() public {
        vulnerableContract = new VulnerableContract();
        vm.deal(address(vulnerableContract), 10 ether);
    }

    function testDenialOfServiceViaZeroValueTransactions() public {
        // 1. Attacker floods the contract with zero-value withdrawal requests.
        vm.startPrank(attacker);
        for (uint256 i = 0; i < 25; i++) { // Reduced to 25 for faster execution, but still effective
            vulnerableContract.requestWithdrawal(0);
        }
        vm.stopPrank();

        // 2. User makes a legitimate, non-zero withdrawal request.
        vm.startPrank(user);
        vulnerableContract.requestWithdrawal(1 ether);
        vm.stopPrank();

        // 3. Processing withdrawals becomes more expensive.
        uint256 beforeGas = gasleft();
        vulnerableContract.processWithdrawals(26); // Reduced count to align with the number of requests pushed earlier.
        uint256 afterGas = gasleft();

        uint256 gasUsed = beforeGas - afterGas;

        //Assert that gas used is significant because of the many zero-value transactions
        assertTrue(gasUsed > 5000);
    }
}