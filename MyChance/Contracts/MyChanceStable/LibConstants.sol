// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


import {IPrizeBond} from './IPrizeBond.sol';


library LibConstants {
    IPrizeBond constant prizeBond = IPrizeBond(0xf6A213158F4c9b2a1c0C7853834011fd9e8497c6);

    uint256 constant PRICE = 10;
    uint256 constant TIME_FOR_NEXT_DRAW = 7 * 1 days;
    uint256 constant MAX_INT = 2**256 - 1;
   
    //AAVE & Token addresses in Avalanche
    address constant daiToken = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;
    address constant usdtToken = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address constant usdcToken = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant aDaiToken = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
    address constant aUsdtToken = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620;
    address constant aUsdcToken = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
}