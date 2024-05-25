// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// user has to pay certain amount to get into the lottery
// random winner (oracle)
//winner gets decided evry x minutes

contract Lottery {

import {VRFConsumerBaseV2} from "@chainlink/contracts@1.1.1/src/v0.8/vrf/VRFConsumerBaseV2.sol";

 error Lottery_NotEnoughEthSent();
 

uint256 private immutable i_enteranceFee; 
address payable[] private players; 
event playersentered(address indexed  player);
constructor (uint256 EnteranceFee) {
    i_enteranceFee = EnteranceFee;
}

function enterLottery() public payable{
    if (msg.value < i_enteranceFee){
    revert Lottery_NotEnoughEthSent();
        }
    players.push(payable(msg.sender));
    emit playersentered(msg.sender);
   
}


function getenteranceFee() public view returns(uint256){
    return i_enteranceFee;
}
 
function getPlayerslist(uint index) public view returns(address){
    return players[index]; // get whole list return players
}

}
  