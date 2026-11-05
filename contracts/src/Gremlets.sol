// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Gremlets
/// @notice 50 one-of-a-kind pixel creatures. Owning token #N unlocks Gremlet #N in the Gremlets desktop app.
/// @dev Deliberately minimal:
///      - Only the contract owner can mint, and only token ids 1..50, each exactly once (ERC-721 forbids re-minting an id).
///      - No payment logic: tokens are minted to the creator and sold on existing marketplaces, so this contract
///        never holds funds.
///      - Metadata lives at `baseURI + id + ".json"`. The owner can update the base URI until `freezeMetadata()`
///        is called; freezing is permanent and emits ERC-4906/permanent events so marketplaces refresh.
contract Gremlets is ERC721, Ownable {
    using Strings for uint256;

    /// @notice Total number of Gremlets that can ever exist. Immutable.
    uint256 public constant MAX_SUPPLY = 50;

    /// @notice Number of Gremlets minted so far.
    uint256 public totalMinted;

    /// @notice Once true, metadata can never change again.
    bool public metadataFrozen;

    string private _baseTokenURI;

    /// @dev ERC-4906 metadata update event (OpenSea and others listen for it).
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);
    /// @dev Emitted once when metadata is frozen forever.
    event MetadataFrozen(string baseURI);

    error InvalidTokenId(uint256 tokenId);
    error MetadataIsFrozen();

    constructor(string memory baseURI_, address initialOwner) ERC721("Gremlets", "GRMLT") Ownable(initialOwner) {
        _baseTokenURI = baseURI_;
    }

    /// @notice Mints Gremlet `tokenId` (1..50) to `to`. Owner only; each id can be minted once.
    function mint(address to, uint256 tokenId) external onlyOwner {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId(tokenId);
        totalMinted += 1;
        _safeMint(to, tokenId);
    }

    /// @notice Mints Gremlets `firstId..lastId` (inclusive) to `to` in one transaction. Owner only.
    function mintRange(address to, uint256 firstId, uint256 lastId) external onlyOwner {
        if (firstId == 0 || firstId > lastId) revert InvalidTokenId(firstId);
        if (lastId > MAX_SUPPLY) revert InvalidTokenId(lastId);
        totalMinted += lastId - firstId + 1;
        for (uint256 id = firstId; id <= lastId; id++) {
            _safeMint(to, id);
        }
    }

    /// @notice Points metadata at a new location (e.g. after moving hosting). Disabled after freezing.
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        if (metadataFrozen) revert MetadataIsFrozen();
        _baseTokenURI = baseURI_;
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    /// @notice Permanently locks metadata. Cannot be undone.
    function freezeMetadata() external onlyOwner {
        if (metadataFrozen) revert MetadataIsFrozen();
        metadataFrozen = true;
        emit MetadataFrozen(_baseTokenURI);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string.concat(_baseTokenURI, tokenId.toString(), ".json");
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId); // ERC-4906
    }
}
