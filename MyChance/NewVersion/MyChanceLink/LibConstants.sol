// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


import {IPrizeBondLINK} from './IPrizeBondLINK.sol';


library LibConstants {
    IPrizeBondLINK constant prizeBond = IPrizeBondLINK(0x6c5721Ad7F50788C50F4e66124cF861dCF6E64F0);

    uint256 constant TIME_FOR_NEXT_DRAW = 7 * 1 days;
    uint256 constant MAX_INT = 2**256 - 1;
   
    //AAVE & Token addresses in Avalanche
    address constant linkToken = 0x5947BB275c521040051D82396192181b413227A3;
    address constant aLinkToken = 0x191c10Aa4AF7C30e871E70C95dB0E4eb77237530;
}