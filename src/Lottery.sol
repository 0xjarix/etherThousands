// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Lottery {
    // errors
    error Lottery__PlayerForgotGrid();
    error Lottery__PlayerCannotRandomizeWhileProvidingNumbers();
    error Lottery__LotteryNotOpen();
    error Lottery__PlayerAlreadyEntered();

    // enum
    enum LotteryState { OPEN, CALCULATING }
    enum GridState { SIMPLE, MULTIPLE }

    // struct
    struct Tuple {
        uint8[5] numbers;
        uint8[2] stars;
    }

    // constants
    uint256 public constant MINIMUM_JACKPOT = 17000 ether;
    uint256 public constant MAXIIMUM_JACKPOT = 250000 ether;
    uint256 public constant SIMPLE_CHANCE_GRID_PRICE = 25 ether;
    uint256 public constant MULTIPLE_CHANCE_GRID_PRICE = 50 ether;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 7;

    // variables
    // @dev Duration of lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    mapping (address => Tuple[]) private s_players;
    address payable private s_players_addresses;
    LotteryState public s_lotteryState;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;

    // events
    event EnteredRaffle(address player);
    event PickedWinner(address indexed winner);

    // constructor
    constructor(
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit) 
    {
        i_interval = 3 days;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lotteryState = LotteryState.OPEN;
    }
    // functions
     function enterLottery(GridState[] gridStates, bool[] flash, Tuple[] numbersAndStars) external payable {
        uint256 nbPaticipants = s_players_addresses.length;
        for (uint256 i = 0; i < nbPaticipants; i++) {
            if (s_players_addresses[i] == msg.sender) {
                revert Lottery__PlayerAlreadyEntered();
            }
        }
        if (s_lotteryState != LotteryState.OPEN) {
            revert Lottery__LotteryNotOpen();
        }
        if (gridStates.count(GridState.SIMPLE) * SIMPLE_CHANCE_GRID + gridStates.count(GridState.MULTIPLE) * MULTIPLE_CHANCE_GRID != msg.value) {
            revert Lottery_PlayerDidNotPayTheExactAmount();
        }
        if (flash.length != numbersAndStars.length) {
            revert Lottery_PlayerForgotGrid();
        }
        s_players.push(payable(msg.sender));
        s_players_addresses.push(msg.sender);
        while (flash) {
            if (flash.pop() == true) {
                if (numbersAndStars.pop()[0].length == 0 && numbersAndStars.pop()[0].length == 0) {
                    // Chainlink VRF
                    uint8[5] numbers = //TODO: Chainlink VRF
                    uint8[2] stars = //TODO: Chainlink VRF
                    numbersAndStars.push(Tuple(numbers, stars));
                } else {
                    revert Lottery_PlayerCannotRandomizeWhileProvidingNumbers();
                }
            }
            if (gridStates.pop() == GridState.SIMPLE) {
                s_players[msg.sender].push(numbersAndStars.pop());
            } else {
                numbers = numbersAndStars.pop()[0];
                for (uint8 i = 1; i < 12; i++) {
                    for (uint8 j = i + 1; j < 13; j++) {
                        s_players[msg.sender].push(Tuple(numbers, [i, j]));
                    }
                }
            }
        }
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner supposed to be picked?
    /**
     * @dev This function is called by the Chainlink Automation nodes to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle must be in the OPEN state
     * 3. The contract has ETH (aka, players) >= 17K ETH
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        internal
        view
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_players.length > 0;
        bool hasEnoughETH = address(this).balance >= 17000 ether;
        upkeepNeeded = timeHasPassed && isOpen && hasPlayers && hasEnoughETH;
        return (upkeepNeeded, "0x0");
    }

    // 1. Get random numbers (5 numbers and 2 stars)
    // 2. Check if one of the players have the exact same numbers
    // 3. Be automatically called
    function performUpkeep(bytes memory /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded)
            revert Raffle__UpkeepNotNeed(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );

        if (block.timestamp - s_lastTimeStamp <= i_interval)
            revert Raffle__NotEnoughTimePassed();
        s_raffleState = RaffleState.CALCULATING;

        // 1. Request the RNG
        // 2. Get a random number
        i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // subscription ID that we funded with LINK in order to make this request
            REQUEST_CONFIRMATIONS, // number of block confirmations for this random number to be considered good
            i_callbackGasLimit, // To make sure we don't overspend on this call
            NUM_WORDS // number of random numbers we want
        );
    }
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // Checks: require statements or if statements => revert
        // Effects
        uint256 nbParticipants = s_players.length;
        uint8[5] numbers;
        uint8[2] stars = [(randomWords[5] % 2) + 1, (randomWords[6] % 2) + 1];
        for(uint8 i = 0; i < 5; i++)
            numbers[i] = [(randomWords[i] % 50) + 1];
        address payable winner = address(0);
        for (uint256 i = 0; i < nbParticipants; i++) {
            uint256 nbGridPerParticipant = s_players[s_players_addresses[i]].length;
            for (uint256 j = 0; j < nbGridPerParticipant; j++) {
                if (s_players[s_players_addresses[i]][j].numbers == numbers && s_players[s_players_addresses[i]][j].stars == stars) {
                    winner = s_players_addresses[i];
                    break;
                }
            }
        }
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        if (winner != address(0)) {
            s_recentWinner = winner;
            emit PickedWinner(winner);
            // Interaction with other contracts (external calls) should be done last to avoid reentrancy attacks
            (bool success, ) = winner.call{value: address(this).balance}("");
            // This if obviously couldn't be put in the Check part even though it is a check, because we're checking whether the call was successful
            if (!success) {
                revert Raffle__TransferFailed();
            }
        } else {
            if (address(this).balance >= 250000 ether) {
                for (uint256 i = 0; i < nbParticipants; i++) {
                    (bool success, ) = s_players_addresses[i].call{value: 250000 ether / nbParticipants}("");
                    if (!success) {
                        revert Raffle__TransferFailed();
                    }
                }
                s_players_addresses = new address payable[](0);
            }
        }
    }
}