// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Gremlets} from "../src/Gremlets.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract GremletsTest is Test {
    Gremlets g;
    address creator = makeAddr("creator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    function setUp() public {
        g = new Gremlets("https://example.test/meta/", creator);
    }

    function test_NameSymbolSupply() public view {
        assertEq(g.name(), "Gremlets");
        assertEq(g.symbol(), "GRMLT");
        assertEq(g.MAX_SUPPLY(), 50);
        assertEq(g.totalMinted(), 0);
        assertEq(g.owner(), creator);
    }

    function test_OwnerMintsAndTokenURI() public {
        vm.prank(creator);
        g.mint(alice, 7);
        assertEq(g.ownerOf(7), alice);
        assertEq(g.balanceOf(alice), 1);
        assertEq(g.totalMinted(), 1);
        assertEq(g.tokenURI(7), "https://example.test/meta/7.json");
    }

    function test_CanMintAll50AndNoMore() public {
        vm.startPrank(creator);
        for (uint256 id = 1; id <= 50; id++) g.mint(creator, id);
        assertEq(g.totalMinted(), 50);
        vm.expectRevert(abi.encodeWithSelector(Gremlets.InvalidTokenId.selector, 51));
        g.mint(creator, 51);
        vm.stopPrank();
    }

    function test_MintRange() public {
        vm.prank(creator);
        g.mintRange(creator, 1, 50);
        assertEq(g.totalMinted(), 50);
        assertEq(g.balanceOf(creator), 50);
        assertEq(g.ownerOf(50), creator);
    }

    function test_MintRangeRejectsBadRanges() public {
        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSelector(Gremlets.InvalidTokenId.selector, 0));
        g.mintRange(creator, 0, 5);
        vm.expectRevert(abi.encodeWithSelector(Gremlets.InvalidTokenId.selector, 51));
        g.mintRange(creator, 45, 51);
        vm.expectRevert(abi.encodeWithSelector(Gremlets.InvalidTokenId.selector, 9));
        g.mintRange(creator, 9, 3);
        g.mintRange(creator, 1, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidSender.selector, address(0)));
        g.mintRange(creator, 10, 12); // overlaps an already-minted id: whole call reverts
        vm.stopPrank();
        assertEq(g.totalMinted(), 10);
    }

    function test_OnlyOwnerCanMintRange() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        g.mintRange(alice, 1, 2);
    }

    function test_RejectsTokenZero() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Gremlets.InvalidTokenId.selector, 0));
        g.mint(alice, 0);
    }

    function test_EachIdIsOneOfAKind() public {
        vm.startPrank(creator);
        g.mint(alice, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidSender.selector, address(0)));
        g.mint(bob, 3);
        vm.stopPrank();
        assertEq(g.totalMinted(), 1);
    }

    function test_OnlyOwnerCanMint() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        g.mint(alice, 1);
    }

    function test_TransfersWork() public {
        vm.prank(creator);
        g.mint(alice, 12);
        vm.prank(alice);
        g.transferFrom(alice, bob, 12);
        assertEq(g.ownerOf(12), bob);
    }

    function test_TokenURIRevertsForUnminted() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 9));
        g.tokenURI(9);
    }

    function test_BaseURIUpdateEmitsRefreshEvent() public {
        vm.prank(creator);
        g.mint(alice, 1);
        vm.expectEmit(address(g));
        emit BatchMetadataUpdate(1, 50);
        vm.prank(creator);
        g.setBaseURI("ipfs://newcid/");
        assertEq(g.tokenURI(1), "ipfs://newcid/1.json");
    }

    function test_OnlyOwnerCanSetBaseURI() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        g.setBaseURI("https://evil.test/");
    }

    function test_FreezeIsPermanent() public {
        vm.startPrank(creator);
        g.freezeMetadata();
        assertTrue(g.metadataFrozen());
        vm.expectRevert(Gremlets.MetadataIsFrozen.selector);
        g.setBaseURI("https://changed.test/");
        vm.expectRevert(Gremlets.MetadataIsFrozen.selector);
        g.freezeMetadata();
        vm.stopPrank();
        assertEq(g.baseURI(), "https://example.test/meta/");
    }

    function test_SupportsInterfaces() public view {
        assertTrue(g.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(g.supportsInterface(0x5b5e139f)); // ERC-721 Metadata
        assertTrue(g.supportsInterface(0x49064906)); // ERC-4906
        assertTrue(g.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(g.supportsInterface(0xffffffff));
    }

    function test_SafeMintToContractWithoutReceiverReverts() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(this)));
        g.mint(address(this), 1);
    }

    /// Fuzz: any id outside 1..50 is rejected; any id inside mints exactly once.
    function testFuzz_MintRange(uint256 id) public {
        vm.startPrank(creator);
        if (id == 0 || id > 50) {
            vm.expectRevert(abi.encodeWithSelector(Gremlets.InvalidTokenId.selector, id));
            g.mint(alice, id);
        } else {
            g.mint(alice, id);
            assertEq(g.ownerOf(id), alice);
        }
        vm.stopPrank();
    }

    /// Fuzz: ownership transfer moves mint rights.
    function testFuzz_OwnershipTransfer(address newOwner) public {
        vm.assume(newOwner != address(0) && newOwner != creator);
        vm.prank(creator);
        g.transferOwnership(newOwner);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, creator));
        g.mint(alice, 1);
        vm.prank(newOwner);
        g.mint(alice, 1);
        assertEq(g.ownerOf(1), alice);
    }
}
