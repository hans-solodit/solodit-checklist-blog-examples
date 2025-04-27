// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview:
 * Checklist Item: Transaction Ordering Dependency
 *
 * This test demonstrates how smart contract logic can be exploited when it's sensitive to
 * transaction ordering. It shows a front-running attack on a simple DEX where a malicious
 * actor observes a pending transaction and executes their own transaction first, causing
 * the victim to receive less tokens than expected.
 *
 * The test also shows the remediation by implementing slippage protection where users can
 * specify minimum output they're willing to accept.
 */

// Simple ERC20 token for testing
contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

// Simplified DEX that's vulnerable to front-running
contract VulnerableDEX {
    TestToken public tokenA;
    TestToken public tokenB;
    uint public reserveA;
    uint public reserveB;

    constructor(address _tokenA, address _tokenB) {
        tokenA = TestToken(_tokenA);
        tokenB = TestToken(_tokenB);
    }

    // Initialize liquidity
    function addLiquidity(uint amountA, uint amountB) external {
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        reserveA += amountA;
        reserveB += amountB;
    }

    // Calculate output amount for a given input
    function _calculateSwapOutput(address tokenIn, uint amountIn) internal view returns (uint amountOut) {
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");

        bool isTokenA = tokenIn == address(tokenA);

        if (isTokenA) {
            amountOut = (reserveB * amountIn) / (reserveA + amountIn);
            require(amountOut < reserveB, "Insufficient liquidity");
        } else {
            amountOut = (reserveA * amountIn) / (reserveB + amountIn);
            require(amountOut < reserveA, "Insufficient liquidity");
        }

        return amountOut;
    }

    // Execute the swap with pre-calculated output
    function _executeSwap(address tokenIn, uint amountIn, uint amountOut, address sender) internal {
        bool isTokenA = tokenIn == address(tokenA);

        if (isTokenA) {
            tokenA.transferFrom(sender, address(this), amountIn);

            // Update reserves
            reserveA += amountIn;
            reserveB -= amountOut;

            // Transfer output tokens to the user
            tokenB.transfer(sender, amountOut);
        } else {
            tokenB.transferFrom(sender, address(this), amountIn);

            reserveB += amountIn;
            reserveA -= amountOut;

            tokenA.transfer(sender, amountOut);
        }
    }

    // Vulnerable swap function (no minimum output)
    function swap(address tokenIn, uint amountIn) external returns (uint amountOut) {
        // Calculate the expected output
        amountOut = _calculateSwapOutput(tokenIn, amountIn);

        // Execute the swap
        _executeSwap(tokenIn, amountIn, amountOut, msg.sender);

        return amountOut;
    }

    // Secure swap function with minimum output requirement
    function swapWithMinimumOutput(
        address tokenIn,
        uint amountIn,
        uint minAmountOut
    ) external returns (uint amountOut) {
        // Calculate the expected output
        amountOut = _calculateSwapOutput(tokenIn, amountIn);

        // Check slippage before executing the swap
        require(amountOut >= minAmountOut, "Slippage too high");

        // Execute the swap
        _executeSwap(tokenIn, amountIn, amountOut, msg.sender);

        return amountOut;
    }
}

contract TransactionOrderingTest is Test {
    VulnerableDEX dex;
    TestToken tokenA;
    TestToken tokenB;

    address victim = address(1);
    address attacker = address(2);
    address liquidityProvider = address(3);

    uint256 initialLiquidityA = 1000 ether;
    uint256 initialLiquidityB = 1000 ether;

    function setUp() public {
        // Deploy tokens with higher initial supply to support both tests
        tokenA = new TestToken("Token A", "TKNA", 100000 ether);
        tokenB = new TestToken("Token B", "TKNB", 100000 ether);

        // Deploy DEX
        dex = new VulnerableDEX(address(tokenA), address(tokenB));

        // Setup DEX with liquidity
        tokenA.transfer(liquidityProvider, 2000 ether);
        tokenB.transfer(liquidityProvider, 2000 ether);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(dex), initialLiquidityA);
        tokenB.approve(address(dex), initialLiquidityB);
        dex.addLiquidity(initialLiquidityA, initialLiquidityB);
        vm.stopPrank();

        // Give fresh tokens to victim and attacker for each test
        // We give them enough for both tests
        tokenA.transfer(victim, 20 ether);
        tokenA.transfer(attacker, 200 ether);
    }

    function testFrontRunningAttack() public {
        // Victim approves DEX to spend tokens
        vm.prank(victim);
        tokenA.approve(address(dex), 10 ether);

        // Attacker approves DEX to spend tokens
        vm.prank(attacker);
        tokenA.approve(address(dex), 100 ether);

        // Capture pre-attack state
        uint victimInitialBalanceB = tokenB.balanceOf(victim);

        // SCENARIO: Victim submits transaction to swap 10 tokenA for tokenB
        // Expected output without front-running
        uint expectedOutput = (dex.reserveB() * 10 ether) / (dex.reserveA() + 10 ether);

        // However, attacker sees this transaction in the mempool and front-runs it
        vm.prank(attacker);
        dex.swap(address(tokenA), 100 ether);

        // Now victim's transaction executes (after attacker's)
        vm.prank(victim);
        uint actualOutput = dex.swap(address(tokenA), 10 ether);

        // Check how much the victim received
        uint victimFinalBalanceB = tokenB.balanceOf(victim);
        uint victimReceivedAmount = victimFinalBalanceB - victimInitialBalanceB;

        // Due to front-running, victim receives less than expected
        assertLt(actualOutput, expectedOutput,
            "Victim should receive less than expected due to front-running");
        assertEq(victimReceivedAmount, actualOutput,
            "Victim received amount should match swap return value");
    }

    function testPreventFrontRunningWithMinimumOutput() public {
        // Victim approves DEX to spend tokens
        vm.prank(victim);
        tokenA.approve(address(dex), 10 ether);

        // Attacker approves DEX to spend tokens
        vm.prank(attacker);
        tokenA.approve(address(dex), 100 ether);

        // Calculate expected output before any swaps
        uint expectedOutput = (dex.reserveB() * 10 ether) / (dex.reserveA() + 10 ether);

        // Attacker front-runs
        vm.prank(attacker);
        dex.swap(address(tokenA), 100 ether);

        // Victim uses swapWithMinimumOutput with expected output as minimum
        vm.prank(victim);
        vm.expectRevert("Slippage too high");
        dex.swapWithMinimumOutput(address(tokenA), 10 ether, expectedOutput);

        // Prove that victim's tokens are safe (not spent) due to the minimum output protection
        assertEq(tokenA.balanceOf(victim), 20 ether, "Victim's tokens should be safe");
    }
}