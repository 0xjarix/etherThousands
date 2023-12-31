// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Lottery {
    // errors
    error Lottery__PlayerForgotGrid();
    error Lottery__PlayerCannotRandomizeWhileProvidingNumbers();
    error Lottery__LotteryNotOpen();
    error Lottery__PlayerInputWrongGridFormat();
    error Lottery__TransferFailed();

    // enum
    enum LotteryState { OPEN, CALCULATING }

    // struct
    struct Tuple {
        uint8[5] numbers;
        uint8[2] stars;
    }

    // constants
    uint256 public constant MINIMUM_JACKPOT = 17000 ether;
    uint256 public constant MAXIIMUM_JACKPOT = 250000 ether;
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
    LotteryState public s_lotteryState;
    uint256 private s_lastTimeStamp;
    address[] private s_recentWinner;
    bool s_maxJackpotReachedAndStillNoWinner;
    uint8 s_numberOfDrawsSinceMaxJackpotReached;
    // events
    event EnteredLottery(address player);
    event PickedWinners(address[] indexed winner);

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
     function enterLottery(bool gridState, uint8[][2] numbersAndStars) external payable {
        if (s_lotteryState != LotteryState.OPEN)
            revert Lottery__LotteryNotOpen();
            
        if (msg.value < 25 + gridState * 25) // gridState == 0 means the grid is simple
            revert Raffle__NotEnoughEthSent();

        if (numbersAndStars.length == 0) 
            revert Lottery__PlayerForgotGrid();

        if (numbersAndStars[0].length != 5 || numbersAndStars[1].length != 2)
            revert Lottery__PlayerInputWrongGridFormat();

        Tuple[] grids;
        for (uint8 i = 0; i < 2; i++) {
            for (uint8 j = 0; j < numbersAndStars[i]; j++) {
                if (numbersAndStars[i][j] < 1 || numbersAndStars[0][i] > 50)
                    revert Lottery__PlayerInputWrongGridFormat();
            }
        }
        if (!gridState) {
            grids[0].numbers = numbersAndStars[0];
            grids[0].stars = numbersAndStars[1];
        }
        else {
            for (uint8 i = 1; i < 12; i++) {
                for (uint8 j = i + 1; j < 13; j++) {
                    grids.push(Tuple(numbersAndStars[0], [i, j]));
                }
            }
        }
        s_players[msg.sender] = grids;
        emit EnteredLottery(msg.sender);
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
        bool hasEnoughETH = address(this).balance >= MINIMUM_JACKPOT;
        upkeepNeeded = (timeHasPassed && isOpen && hasPlayers && hasEnoughETH) || s_maxJackpotReachedAndStillNoWinner;
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
        uint8[][2] memory numbersAndStars;
        for (uint8 i = 0; i < 2; i++) {
            uint8 len = i ? 2 : 5;
            for (uint8 j = 0; j < len; j++) {
                numbersAndStars[i][j] = randomWords[i * 5 + j] % 50 + 1;
            }
        }
        address payable[] winners;
        if (address(this).balance < MAXIIMUM_JACKPOT)
            winners = pickWinnerBeforeMax();
        else{
            if(s_numberOfDrawsSinceMaxJackpotReached == 0)
                s_maxJackpotReachedAndStillNoWinner = true;
            if (s_numberOfDrawsSinceMaxJackpotReached < 5) {
                s_numberOfDrawsSinceMaxJackpotReached++;
                return;
            }
            winners = pickWinnerAfterMax();
        }
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_numberOfDrawsSinceMaxJackpotReached = 0;
        s_maxJackpotReachedAndStillNoWinner = false;
        if (winners.length != 0) {
            s_recentWinners = winners;
            // Interaction with other contracts (external calls) should be done last to avoid reentrancy attacks
            for (uint256 i = 0; i < winners.length; i++) {
                address payable winner = winners[i];
                (bool success, ) = winner.call{value: address(this).balance / winners.length}("");
                // This if obviously couldn't be put in the Check part even though it is a check, because we're checking whether the call was successful
                if (!success)
                    revert Lottery__TransferFailed();
            }
            emit PickedWinners(winners);
        }
    }

    function pickWinnerAfterMax() internal returns (address payable[] winners){
        uint256 nbParticipants = s_players.length;
        for (uint256 i = 0; i < nbParticipants; i++) {
            Tuple[] memory grids = s_players[i];
            for (uint256 j = 0; j < grids.length; j++) {
                Tuple memory grid = grids[j];
                uint8[5] memory numbers = grid.numbers;
                bool valid = true;
                for (uint8 k = 0; k < 5; k++) {
                    if (numbers[k] != numbersAndStars[0][k]) {
                        valid = false;
                        break;
                    }
                }
                if (valid) {
                    uint8[2] memory stars = grid.stars;
                    for (uint8 k = 0; k < 2; k++) {
                        if (stars[k] != numbersAndStars[1][k]) {
                            valid = false;
                            break;
                        }
                    }
                    if (valid) {
                        winners.push(payable(s_players[i]));
                    }
                }
            }
        }
        return winners;
    }

    function pickWinnerBeforeMax() internal returns (address payable[] winners){
        uint256 nbParticipants = s_players.length;
        for (uint256 i = 0; i < nbParticipants; i++) {
            Tuple[] memory grids = s_players[i];
            for (uint256 j = 0; j < grids.length; j++) {
                Tuple memory grid = grids[j];
                uint8[5] memory numbers = grid.numbers;
                bool valid = true;
                for (uint8 k = 0; k < 5; k++) {
                    if (numbers[k] != numbersAndStars[0][k]) {
                        valid = false;
                        break;
                    }
                }
                if (valid) {
                    uint8[2] memory stars = grid.stars;
                    for (uint8 k = 0; k < 2; k++) {
                        if (stars[k] != numbersAndStars[1][k]) {
                            valid = false;
                            break;
                        }
                    }
                    if (valid) {
                        winners.push(payable(s_players[i]));
                    }
                }
            }
        }
        return winners;
    }
}

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