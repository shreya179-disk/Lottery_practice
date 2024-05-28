// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Lottery.sol";

contract LotteryScript is Script {
    function run() external {
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 entranceFee = vm.envUint("ENTRANCE_FEE");
        bytes32 gasLane = vm.envBytes32("GAS_LANE");
        uint64 subscriptionId = uint64(vm.envUint("SUBSCRIPTION_ID"));
        uint32 callbackGasLimit = uint32(vm.envUint("CALLBACK_GAS_LIMIT")); // Explicitly cast to uint32

        vm.startBroadcast();

        Lottery lottery = new Lottery(
            vrfCoordinator,
            entranceFee,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );

        vm.stopBroadcast();
    }
}
