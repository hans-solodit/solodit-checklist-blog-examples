// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-DOSA-3

 * This test demonstrates a Denial-of-Service (DOS) vulnerability (SOL-AM-DOSA-3) in a group staking contract
 * where an entire group of users can be permanently locked out of withdrawing their staked tokens if just a single member
 * of the group is blacklisted by the staked token. The test verifies that if any user in a staking group is blacklisted
 * by the token contract *after* staking, group withdrawals will fail for all members, effectively locking everyone's funds.
 */

contract GroupStaking {
    IERC20 public token;

    struct StakingGroup {
        uint256 id;
        uint256 totalAmount;
        address[] members;
        uint256[] weights;
        bool exists;
    }

    // Mapping from group ID to group data
    mapping(uint256 => StakingGroup) public stakingGroups;
    // Current group ID counter
    uint256 public nextGroupId = 1;

    constructor(IERC20 _token) {
        token = _token;
    }

    // Create a new staking group
    function createStakingGroup(address[] calldata _members, uint256[] calldata _weights) external returns (uint256) {
        require(_members.length > 0, "Empty members list");
        require(_members.length == _weights.length, "Members and weights length mismatch");

        // Validate weights sum to 100%
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        require(totalWeight == 100, "Weights must sum to 100");

        uint256 groupId = nextGroupId;
        stakingGroups[groupId] = StakingGroup({
            id: groupId,
            totalAmount: 0,
            members: _members,
            weights: _weights,
            exists: true
        });

        nextGroupId++;
        return groupId;
    }

    // Stake tokens to a group
    function stakeToGroup(uint256 _groupId, uint256 _amount) external {
        require(stakingGroups[_groupId].exists, "Group does not exist");
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        stakingGroups[_groupId].totalAmount += _amount;
    }

    // Withdraw tokens from a group with rewards distributed according to weights
    function withdrawFromGroup(uint256 _groupId, uint256 _amount) external {
        StakingGroup storage group = stakingGroups[_groupId];
        require(group.exists, "Group does not exist");
        require(group.totalAmount >= _amount, "Insufficient group balance");

        // Only a group member can initiate a withdrawal
        bool isMember = false;
        for (uint256 i = 0; i < group.members.length; i++) {
            if (group.members[i] == msg.sender) {
                isMember = true;
                break;
            }
        }
        require(isMember, "Not a group member");

        // Update the group's total amount
        group.totalAmount -= _amount;

        // Distribute the withdrawn amount to all members according to their weights
        // VULNERABLE: If any member is blacklisted, the entire distribution fails
        for (uint256 i = 0; i < group.members.length; i++) {
            uint256 memberShare = (_amount * group.weights[i]) / 100;
            if (memberShare > 0) {
                token.transfer(group.members[i], memberShare);
            }
        }
    }

    // Get group info
    function getGroupInfo(uint256 _groupId) external view returns (
        uint256 id,
        uint256 totalAmount,
        address[] memory members,
        uint256[] memory weights
    ) {
        StakingGroup storage group = stakingGroups[_groupId];
        require(group.exists, "Group does not exist");

        return (
            group.id,
            group.totalAmount,
            group.members,
            group.weights
        );
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

contract GroupStakingTest is Test {
    GroupStaking public stakingContract;
    BlacklistableToken public token;

    address public admin = address(this);
    address public user1 = address(1);
    address public user2 = address(2);
    address public user3 = address(3);

    uint256 public groupId;

    function setUp() public {
        // Deploy the BlacklistableToken
        token = new BlacklistableToken("Test Token", "TT");

        // Deploy the GroupStaking contract
        stakingContract = new GroupStaking(IERC20(address(token)));

        // Mint tokens to admin for staking
        token.mint(admin, 100 ether);
        token.approve(address(stakingContract), 100 ether);

        // Create a staking group with 3 members
        address[] memory members = new address[](3);
        members[0] = user1;
        members[1] = user2;
        members[2] = user3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 50; // 50%
        weights[1] = 30; // 30%
        weights[2] = 20; // 20%

        groupId = stakingContract.createStakingGroup(members, weights);

        // Stake to the group
        stakingContract.stakeToGroup(groupId, 100 ether);
    }

    function testGroupStakingDOS() public {
        // Verify initial group state
        (uint256 id, uint256 totalAmount, address[] memory members, uint256[] memory weights) =
            stakingContract.getGroupInfo(groupId);

        assertEq(id, groupId);
        assertEq(totalAmount, 100 ether);
        assertEq(members.length, 3);
        assertEq(weights[0], 50);
        assertEq(weights[1], 30);
        assertEq(weights[2], 20);

        // Act: Blacklist just one user in the group (user2)
        token.blacklist(user2);

        // Try to withdraw as user1 (non-blacklisted)
        vm.prank(user1);

        // Assert: Entire group withdrawal fails because user2 is blacklisted
        vm.expectRevert("Account is blacklisted");
        stakingContract.withdrawFromGroup(groupId, 10 ether);

        // Verify group balance remains unchanged
        (,uint256 remainingAmount,,) = stakingContract.getGroupInfo(groupId);
        assertEq(remainingAmount, 100 ether);
    }

    function testGroupStakingWithAllMembersNonBlacklisted() public {
        // Verify that withdrawal works when no users are blacklisted
        vm.prank(user1);
        stakingContract.withdrawFromGroup(groupId, 10 ether);

        // Verify group balance is updated correctly
        (,uint256 remainingAmount,,) = stakingContract.getGroupInfo(groupId);
        assertEq(remainingAmount, 90 ether);

        // Verify token balances of each user
        assertEq(token.balanceOf(user1), 5 ether);   // 50% of 10 ether
        assertEq(token.balanceOf(user2), 3 ether);   // 30% of 10 ether
        assertEq(token.balanceOf(user3), 2 ether);   // 20% of 10 ether
    }
}
