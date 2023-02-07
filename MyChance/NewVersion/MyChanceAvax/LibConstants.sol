// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


import {IPrizeBondAVAX} from './IPrizeBondAVAX.sol';


library LibConstants {
    IPrizeBondAVAX constant prizeBond = IPrizeBondAVAX(0x8A07dfd40F8137F3336551DDfe7B1b24A29bA413);
    
    uint256 constant TIME_FOR_NEXT_DRAW = 7 * 1 days;
    uint256 constant MAX_INT = 2**256 - 1;
   
    //AAVE & Token addresses in Avalanche
    address constant linkToken = 0x5947BB275c521040051D82396192181b413227A3;
    address constant avWAVAXToken = 0xDFE521292EcE2A4f44242efBcD66Bc594CA9714B;
}