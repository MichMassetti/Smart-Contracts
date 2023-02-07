// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface IPrizeBondAVAX is IERC721 {
    function safeMint(address to) external returns(uint256);

    function safeBurn(uint256 tokenId) external;
        
    function setMyChance(address _myChanceAdd, address _myChanceMigration) external;

}