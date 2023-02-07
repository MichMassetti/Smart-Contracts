// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface IPrizeBond is IERC721 {
    enum Assets { DAI, USDT, USDC }

    function getAssetType(uint256 tokenId) external view returns(Assets);

    function safeMint(address to, Assets asset) external returns(uint256);

    function safeBurn(uint256 tokenId) external;

    function setMyChance(address _myChanceAdd, address _myChanceMigration) external;
}