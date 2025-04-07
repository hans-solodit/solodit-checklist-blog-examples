pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Overview:
 * Checklist Item ID: SOL-AM-FrA-2
 *
 * This test demonstrates a front-running attack on an NFT refinance process.
 * The attack occurs when an attacker monitors the mempool for NFT approvals
 * and front-runs the original owner by calling refinance first, becoming
 * the creditor for the NFT.
 */

interface INFT is IERC721 {
    function mint(address to, uint256 tokenId) external;
}

contract NFTRefinanceMarket is Ownable {
    INFT public nft;
    mapping(uint256 => address) public tokenCreditors;

    constructor(INFT _nft) Ownable(msg.sender) {
        nft = _nft;
    }

    function refinance(uint256 _tokenId) external {
        // Check if this contract has approval to transfer the NFT
        require(nft.getApproved(_tokenId) == address(this), "Not approved");
        address originalOwner = nft.ownerOf(_tokenId);

        // Pull the NFT into this contract as collateral
        nft.transferFrom(originalOwner, address(this), _tokenId);

        // Record the caller as the creditor for this NFT
        tokenCreditors[_tokenId] = msg.sender;
    }
}

contract NFT is ERC721, Ownable, INFT {
    constructor() ERC721("TestNFT", "NFT") Ownable(msg.sender) {}

    function mint(address to, uint256 tokenId) external override onlyOwner {
        _mint(to, tokenId);
    }
}

contract FrontRunningTest is Test {
    NFTRefinanceMarket nftRefinanceMarket;
    NFT nft;
    address owner;
    address user;
    address attacker;
    uint256 tokenId = 1;

    function setUp() public {
        owner = vm.addr(1);
        user = vm.addr(2);
        attacker = vm.addr(3);

        vm.startPrank(owner);
        nft = new NFT();
        nftRefinanceMarket = new NFTRefinanceMarket(INFT(address(nft)));
        nft.mint(user, tokenId);
        vm.stopPrank();
    }

    function testFrontRunRefinance() public {
        // 1. User approves the contract to refinance their NFT
        assertEq(nft.ownerOf(tokenId), user);
        vm.startPrank(user);
        nft.approve(address(nftRefinanceMarket), tokenId);
        assertEq(nft.getApproved(tokenId), address(nftRefinanceMarket));
        vm.stopPrank();

        // 2. Attacker monitors the mempool, and before the user calls refinance, the attacker calls refinance
        vm.startPrank(attacker);

        // Simulate the attacker front-running the transaction
        // In a real scenario, the attacker would increase the gas price to get their transaction included first
        nftRefinanceMarket.refinance(tokenId);

        // Verify that the attacker is now marked as the creditor for this NFT
        assertEq(nftRefinanceMarket.tokenCreditors(tokenId), attacker);

        // Verify that the NFT now belongs to the contract
        assertEq(nft.ownerOf(tokenId), address(nftRefinanceMarket));
        vm.stopPrank();

        // 3. User tries to refinance the NFT, but it has already been refinanced by the attacker
        vm.startPrank(user);
        vm.expectRevert("Not approved");
        nftRefinanceMarket.refinance(tokenId);
        vm.stopPrank();
    }
}
