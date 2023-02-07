// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;


import "./Roles.sol";


contract Charities is Roles {
    mapping(address => bool) public charities;
    address[] public aCharities;
    uint256 currentCharity = 0;

    function _enableCharity(address _charity, bool _enabled) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(charities[_charity] != _enabled, "Already done");

        charities[_charity] = _enabled;

        if (_enabled) {
            aCharities.push(_charity);
        } else {
            bool doNow = false;
            for (uint i = 0; i<aCharities.length-1; i++){
                if (aCharities[i] == _charity) {
                    doNow = true;                    
                }
                if (doNow) {
                    aCharities[i] = aCharities[i+1];
                }
            }
            aCharities.pop();
        }
    }

    constructor() {
        _enableCharity(0x0B98d3b5ad68992559F9684A70310e48aE892A48, true);
        _enableCharity(0x0DdcAE532E4b1B31500Cd29d7AC110F052e30645, true);
        _enableCharity(0x74CE447d787313E4555C0D3E03C3934E0C0bDB6A, true);
        _enableCharity(0xE9bFF54D628DBe3C8C59f74ccb1aB4560a1713C0, true);
        _enableCharity(0xF8fF6e693b9B8C6A25891cC0bAB53960aac95453, true);
    }
}