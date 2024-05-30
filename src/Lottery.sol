// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// user has to pay certain amount to get into the lottery
// random winner (oracle)
// winner gets decided every x minutes
import {VRFConsumerBaseV2} from "lib/chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "lib/chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {AutomationCompatibleInterface} from "lib/chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract Lottery is VRFConsumerBaseV2, AutomationCompatibleInterface {

    enum LotteryState {
        OPEN,
        CALCULATING,
        CLOSE
    }

    error Lottery_NotEnoughEthSent();
    error Lottery_NotOpenedYet();
    error lottery__upkeepNOTNEEDED();

    event playersentered(address indexed player);
    event RequestedLotterywinner(uint indexed requestId);
    event WinnerPicked(address indexed winner);

    uint256 private immutable i_enteranceFee;
    address payable[] private players;
    LotteryState internal s_LotteryState;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; // Random number verification
    bytes32 private immutable i_gaslane;
    address private immutable i_owner;
    uint64 private immutable i_subscription_id;
    uint16 private constant REQUEST_CONFIRMATIONS = 4;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    address[] private s_Winners;
    uint256 private s_lastTimeStamp;
    uint256 private immutable interval = 5 days;

    constructor(
        address vrfCoordinator,
        uint256 EnteranceFee,
        bytes32 gaslane,
        uint64 subscription_id,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_enteranceFee = EnteranceFee;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_owner = msg.sender;
        i_gaslane = gaslane;
        i_subscription_id = subscription_id;
        i_callbackGasLimit = callbackGasLimit;
        s_LotteryState = LotteryState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == i_owner, "Caller is not the owner");
        _;
    }

    function enterLottery() public payable {
        if (msg.value < i_enteranceFee) {
            revert Lottery_NotEnoughEthSent();
        }
        if (s_LotteryState != LotteryState.OPEN) {
            revert Lottery_NotOpenedYet();
        }
        players.push(payable(msg.sender));
        emit playersentered(msg.sender);
    }

    // upkeep to be true 
    // 1. Time must have passed 
    // 2. Lottery must have at least one player and some eth
    // 3. Our subscription must be funded 
    // 4. Lottery should be in open state
    function checkUpkeep(bytes memory  /* checkData */) public view override returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool is_Open = (LotteryState.OPEN == s_LotteryState);
        bool enough_Players = players.length > 1;
        bool time_Passed = (block.timestamp - s_lastTimeStamp) > interval;
        bool has_Balance = address(this).balance > 0;
        upkeepNeeded = (is_Open && enough_Players && time_Passed && has_Balance);
    }

    function performUpkeep(bytes calldata /* checkData */) external override onlyOwner  {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if(!upkeepNeeded){
            revert lottery__upkeepNOTNEEDED();
        }
        s_LotteryState = LotteryState.CALCULATING; 
        // Will revert if subscription is not set and funded.
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gaslane,
            i_subscription_id,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedLotterywinner(requestId);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {
        uint256 Indexofwinner = randomWords[0] % players.length;
        address payable recentWinner = players[Indexofwinner];
        s_Winners.push(recentWinner);
        s_LotteryState = LotteryState.OPEN;
        delete players;
        s_lastTimeStamp = block.timestamp;
        recentWinner.transfer(address(this).balance);
        emit WinnerPicked(recentWinner);
    }

    function mockFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        fulfillRandomWords(requestId, randomWords);
    }

    function getenteranceFee() public view returns (uint256) {
        return i_enteranceFee;
    }

    function getPlayerslist(uint index) public view returns (address) {
        return players[index]; // get whole list return players
    }

    function getPreviousWinnersList() public view returns (address[] memory) {
        return s_Winners;
    }

    function getLotteryState() public view returns (LotteryState) {
        return s_LotteryState;
    }
    function getInterval() public pure  returns (uint256) {
        return interval;
    }

    function getlatestTimestap() public view returns(uint){
        return s_lastTimeStamp;
    }
}

