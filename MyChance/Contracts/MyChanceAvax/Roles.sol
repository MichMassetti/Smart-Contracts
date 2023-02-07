// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


import "@openzeppelin/contracts/access/AccessControl.sol";


contract Roles is AccessControl {
   
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MIGRATOR_ROLE = keccak256("MIGRATOR_ROLE");
    bytes32 public constant FEES_ROLE = keccak256("FEES_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MIGRATOR_ROLE, msg.sender);
        _grantRole(FEES_ROLE, msg.sender);
    }
}