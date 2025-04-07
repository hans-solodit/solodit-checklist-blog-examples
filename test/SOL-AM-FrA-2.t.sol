pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-FrA-2
 *
 * This test demonstrates a front-running attack on a two-step withdrawal process.
 * The attack occurs between the approval transaction and the actual withdrawal transaction,
 * where an attacker can monitor the mempool for approvals and then call withdraw before the intended user.
 */

interface INFT is IERC721 {
    function mint(address to, uint256 tokenId) external;
}

contract VulnerableWithdrawal is Ownable {
    INFT public nft;

    constructor(INFT _nft) Ownable(msg.sender) {
        nft = _nft;
    }

    function withdraw(uint256 _tokenId) external {
        // Anyone can withdraw if they have approval.  A frontrunner can steal the tokens
        require(nft.getApproved(_tokenId) == address(this), "Not approved");
        nft.transferFrom(nft.ownerOf(_tokenId), msg.sender, _tokenId);
    }
}

contract NFT is ERC721, Ownable, INFT {
    constructor() ERC721("TestNFT", "NFT") Ownable(msg.sender) {}

    function mint(address to, uint256 tokenId) external override onlyOwner {
        _mint(to, tokenId);
    }
}

contract FrontRunningTest is Test {
    VulnerableWithdrawal public vulnerableWithdrawal;
    NFT public nft;
    address public owner;
    address public user;
    address public attacker;
    uint256 public tokenId = 1;

    function setUp() public {
        owner = vm.addr(1);
        user = vm.addr(2);
        attacker = vm.addr(3);

        vm.startPrank(owner);
        nft = new NFT();
        vulnerableWithdrawal = new VulnerableWithdrawal(INFT(address(nft)));
        nft.mint(user, tokenId);
        vm.stopPrank();
    }

    function testFrontRunWithdrawal() public {
        // 1. User approves the contract to withdraw
        assertEq(nft.ownerOf(tokenId), user); // User is the owner of the NFT
        vm.startPrank(user);
        nft.approve(address(vulnerableWithdrawal), tokenId);
        assertEq(nft.getApproved(tokenId), address(vulnerableWithdrawal));
        vm.stopPrank();

        // 2. Attacker monitors the mempool, and before the user calls withdraw, the attacker calls withdraw
        vm.startPrank(attacker);

        // Simulate the attacker front-running the transaction.  In a real front-running scenario, the attacker
        // would increase the gas price to get miners to include their transaction first.
        // Create the VulnerableWithdrawal contract as the Attacker
        vulnerableWithdrawal.withdraw(tokenId);

        // Verify that the NFT now belongs to the attacker after the front-running attack.
        assertEq(nft.ownerOf(tokenId), address(attacker));
        vm.stopPrank();

        // 3. User tries to withdraw the NFT, but it has already been stolen by the attacker
        vm.startPrank(user);
        vm.expectRevert("Not approved");
        vulnerableWithdrawal.withdraw(tokenId);
        vm.stopPrank();
    }
}