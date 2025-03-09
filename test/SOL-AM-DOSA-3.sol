// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview: This test demonstrates a Denial-of-Service (DOS) vulnerability (SOL-AM-DOSA-3) in a staking contract
 * where a user can be permanently locked out of withdrawing their staked tokens if they are blacklisted by the staked token.
 * The test verifies that if a user is blacklisted by the token contract *after* staking, their withdrawal will fail,
 * effectively locking their funds.
 */

contract Staking {
    IERC20 public token;
    mapping(address => uint256) public stakingBalance;

    constructor(IERC20 _token) {
        token = _token;
    }

    function stake(uint256 _amount) external {
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        stakingBalance[msg.sender] += _amount;
    }

    function withdraw(uint256 _amount) external {
        require(stakingBalance[msg.sender] >= _amount, "Insufficient balance");
        stakingBalance[msg.sender] -= _amount;
        // Vulnerable line: If `msg.sender` is blacklisted, this transfer will revert, blocking the withdraw
        token.transfer(msg.sender, _amount);
    }
}

contract BlacklistableToken is ERC20 {
    mapping(address => bool) public blacklisted;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function blacklist(address account) public {
        blacklisted[account] = true;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(!blacklisted[msg.sender], "Account is blacklisted");
        require(!blacklisted[recipient], "Account is blacklisted");
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(!blacklisted[sender], "Account is blacklisted");
        require(!blacklisted[recipient], "Account is blacklisted");
        return super.transferFrom(sender, recipient, amount);
    }
}

contract StakingTest is Test {
    Staking public stakingContract;
    BlacklistableToken public token;
    address public user = address(1);

    function setUp() public {
        // Deploy the BlacklistableToken
        token = new BlacklistableToken("Test Token", "TT");

        // Deploy the Staking contract, passing the token's address
        stakingContract = new Staking(IERC20(address(token)));

        // Mint tokens to the user
        token.mint(user, 100 ether);
        token.approve(address(stakingContract), 100 ether);
    }

    function testBlacklistingDOS() public {
        // Arrange: User stakes tokens
        uint256 stakeAmount = 50 ether;
        vm.startPrank(user);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        // Act: Blacklist the user
        token.blacklist(user);

        // Assert: User cannot withdraw, resulting in DOS
        vm.prank(user);
        vm.expectRevert("Account is blacklisted");
        stakingContract.withdraw(stakeAmount);
    }
}