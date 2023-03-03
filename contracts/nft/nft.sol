// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { BaseERC721 } from "./base_erc721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Nft is Ownable, BaseERC721 {
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    using Strings for uint256;
    string baseURI;
    uint256 public constant BATCH_SIZE = 10;
    uint256 public constant MAX_SUPPLY = 1000000;

    constructor(
        string memory name,
        string memory symbol,
        string memory uri
    ) BaseERC721(name, symbol, BATCH_SIZE, MAX_SUPPLY) {
        baseURI = uri;
    }

    function mint(uint256 amount) external onlyOwner {
        _safeMint(msg.sender, amount);
    }

    function mintTo(address[] memory addrs) external onlyOwner {
        require(addrs.length <= BATCH_SIZE, "addresses too much");
        for (uint256 i = 0; i < addrs.length; i++) {
            _safeMint(addrs[i], 1);
        }
    }

    function setBaseURI(string memory _baseURI_) external onlyOwner {
        baseURI = _baseURI_;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (_exists(tokenId)) {
            return
                string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
        }

        return "unknown.json";
    }

    function updateMetadata(uint256 _fromTokenId, uint256 _toTokenId) external onlyOwner {
        emit BatchMetadataUpdate(_fromTokenId, _toTokenId);
    }
}
