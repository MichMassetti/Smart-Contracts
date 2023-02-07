// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";


abstract contract RandomRequester is VRFConsumerBaseV2, ConfirmedOwner {
    VRFCoordinatorV2Interface coordinator;
    LinkTokenInterface linkToken;
    address constant vrfCoordinator = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;
    address constant link = 0x5947BB275c521040051D82396192181b413227A3;
    uint32 callbackGasLimit = 800000;

     constructor()
        VRFConsumerBaseV2(vrfCoordinator)
        ConfirmedOwner(msg.sender)
    {
        coordinator = VRFCoordinatorV2Interface(vrfCoordinator);
    }

    function _randomnessRequest() internal returns(uint256) {   
        return coordinator.requestRandomWords(
            0x06eb0e2ea7cca202fc7c8258397a36f33d88568d2522b37aaa3b14ff6ee1b696, //keyHash
            38, //s_subscriptionId
            3, //requestConfirmations
            callbackGasLimit,
            1
        );
    }
}