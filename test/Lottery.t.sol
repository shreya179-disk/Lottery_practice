// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Lottery.sol";

contract VRFCoordinatorV2Mock {
    event RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId);
    event RandomWordsFulfilled(uint256 requestId, uint256[] randomWords);

    uint256 private currentRequestId = 1;

    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minReqConf,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId) {
        requestId = currentRequestId++;
        emit RandomWordsRequested(keyHash, requestId);
    }

    function fulfillRandomWords(uint256 requestId, address consumer) external {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = uint256(keccak256(abi.encode(requestId, block.timestamp)));
        (bool success,) = consumer.call(abi.encodeWithSignature("mockFulfillRandomWords(uint256,uint256[])", requestId, randomWords));
        require(success, "fulfillment failed");
        emit RandomWordsFulfilled(requestId, randomWords);
    }
}

contract LotteryTest is Test {
    Lottery lottery;
    VRFCoordinatorV2Mock vrfCoordinatorV2Mock;
    address deployer = address(1);
    address player = address(2);
    uint256 lotteryEntranceFee;
    uint256 interval;
    event playersentered(address indexed player);

    function setUp() public {
        // Set the block.timestamp so tests are consistent
        vm.warp(1);

        // Deploy the VRFCoordinatorV2Mock contract
        vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock();

        // Deploy the Lottery contract
        lottery = new Lottery(
            address(vrfCoordinatorV2Mock), // vrfCoordinator
            0.1 ether, // EntranceFee
            bytes32(0), // gaslane
            0, // subscription_id
            200000 // callbackGasLimit
        );

        // Set entrance fee and interval
        lotteryEntranceFee = lottery.getenteranceFee();
        interval = lottery.getInterval();

        // Give some ETH to the player for testing
        vm.deal(player, 1 ether);
    }

    function testConstructorInitializesLotteryCorrectly() public {
        uint256 lotteryState = uint256(lottery.getLotteryState());
        assertEq(lotteryState, 0);
        assertEq(interval, 5 days); // Directly comparing with the constant interval
    }

    function testEnterLotteryRevertsIfNotEnoughETH() public {
        vm.prank(player);
        vm.expectRevert("Lottery_NotEnoughEthSent");
        lottery.enterLottery{value: 0}();
    }

    function testEnterLotteryRecordsPlayer() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();
        assertEq(lottery.getPlayerslist(0), player);
    }

    function testEnterLotteryEmitsEvent() public {
        vm.prank(player);
        vm.expectEmit(true, true, true, true);
        emit playersentered(player);
        lottery.enterLottery{value: lotteryEntranceFee}();
    }

    function testEnterLotteryRevertsIfLotteryIsCalculating() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        // Move time forward to exceed the interval
        vm.warp(block.timestamp + interval + 1);

        // Perform upkeep to change state to calculating
        vm.prank(deployer);
        lottery.performUpkeep("");

        vm.prank(player);
        vm.expectRevert("Lottery_NotOpenedYet");
        lottery.enterLottery{value: lotteryEntranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfNoETHSent() public {
        vm.warp(block.timestamp + interval + 1);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfLotteryIsNotOpen() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.prank(deployer);
        lottery.performUpkeep("");

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughTimePassed() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        vm.warp(block.timestamp + interval - 5);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueIfAllConditionsMet() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        vm.warp(block.timestamp + interval + 1);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepOnlyRunsIfCheckUpkeepTrue() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.prank(deployer);
        lottery.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepFalse() public {
        vm.prank(deployer);
        vm.expectRevert("lottery__upkeepNOTNEEDED");
        lottery.performUpkeep("");
    }

    function testPerformUpkeepUpdatesStateAndEmitsRequestId() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        vm.warp(block.timestamp + interval + 1);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);

        vm.recordLogs();
        vm.prank(deployer);
        lottery.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], keccak256("RequestedLotterywinner(uint256)"));

        uint256 lotteryState = uint256(lottery.getLotteryState());
        assertEq(lotteryState, 1);
    }

    function testFulfillRandomWordsRevertsIfNotCalledAfterPerformUpkeep() public {
        vm.prank(player);
        lottery.enterLottery{value: lotteryEntranceFee}();

        vm.expectRevert("nonexistent request");
        vrfCoordinatorV2Mock.fulfillRandomWords(0, address(lottery));
    }

    function testFulfillRandomWordsPicksWinnerResetsAndSendsMoney() public {
        uint256 additionalEntrances = 3;
        uint256 startingIndex = 3;

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
            address newPlayer = address(uint160(i));
            vm.deal(newPlayer, 1 ether);
            vm.prank(newPlayer);
            lottery.enterLottery{value: lotteryEntranceFee}();
        }

        vm.warp(block.timestamp + interval + 1);
        vm.prank(deployer);
        lottery.performUpkeep("");

        uint256 startingBalance = player.balance;
        vm.recordLogs();

        vm.prank(deployer);
        vrfCoordinatorV2Mock.fulfillRandomWords(1, address(lottery));

        // Check logs for WinnerPicked event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], keccak256("WinnerPicked(address)"));

        address recentWinner = lottery.getPreviousWinnersList()[0];
        uint256 lotteryState = uint256(lottery.getLotteryState());
        uint256 winnerBalance = player.balance;

        assertEq(recentWinner, player);
        assertEq(lotteryState, 0);
        assertEq(
            winnerBalance,
            startingBalance + lotteryEntranceFee * (additionalEntrances + 1)
        );
    }
}
