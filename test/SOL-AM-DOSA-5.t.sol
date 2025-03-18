pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-DOSA-5
 *
 * This test demonstrates a Denial-of-Service (DOS) vulnerability in a token streaming contract
 * where low-decimal tokens, when combined with a long stream duration, can cause a DOS.
 * The TokenStream contract distributes tokens over a period, but if tokensPerSecond rounds to zero
 * due to integer division with low-decimal tokens, the distribution function will be permanently blocked.
 */

contract TokenStream {
    IERC20 public token;
    uint256 public streamDuration;
    uint256 public tokensPerSecond;

    constructor(IERC20 _token, uint256 _streamDuration, uint256 _tokensPerSecond) {
        token = _token;
        streamDuration = _streamDuration;
        tokensPerSecond = _tokensPerSecond;
    }

    function distributeTokens(address recipient) external {
        uint256 balance = token.balanceOf(address(this));
        uint256 amount = tokensPerSecond * streamDuration;

        uint256 tokensToSend = amount > balance ? balance : amount;

        require(tokensToSend > 0, "Insufficient tokens to stream");
        token.transfer(recipient, tokensToSend);
    }
}

contract LowDecimalToken is ERC20 {
    constructor() ERC20("LowDecimalToken", "LDT") {
        _mint(msg.sender, 100000 * (10 ** decimals()));
    }

    function decimals() public view virtual override returns (uint8) {
        return 1; // Simulate a low decimal token
    }
}

contract TokenStreamTest is Test {
    TokenStream public tokenStream;
    LowDecimalToken public lowDecimalToken;
    address public recipient;

    function setUp() public {
        recipient = address(1);
        lowDecimalToken = new LowDecimalToken();

        // Simulate a scenario with low decimals and long duration,
        // potentially causing tokensPerSecond to be small enough to round to 0.
        uint256 stream_duration = 1000;
        // If the total amount is small enough, and duration is long, each second will transfer 0 tokens
        uint256 total_tokens = 10;
        uint256 tokens_per_second = total_tokens / stream_duration;

        tokenStream = new TokenStream(lowDecimalToken, stream_duration, tokens_per_second);
        lowDecimalToken.transfer(address(tokenStream), total_tokens * (10 ** lowDecimalToken.decimals()));
    }

    function testDOSWithLowDecimalTokens() public {
        // Attempting to distribute tokens should fail due to rounding to zero.
        vm.expectRevert("Insufficient tokens to stream");
        tokenStream.distributeTokens(recipient);
    }
}