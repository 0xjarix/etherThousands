// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
contract Lottery is VRFConsumerBaseV2, AutomationCompatibleInterface {
    // errors
    error Lottery__PlayerForgotGrid();
    error Lottery__PlayerCannotRandomizeWhileProvidingNumbers();
    error Lottery__LotteryNotOpen();
    error Lottery__PlayerInputWrongGridFormat();
    error Lottery__TransferFailed();
    error Lottery__NotEnoughEthSent();
    error Lottery__NotEnoughTimePassed();
    error Lottery__UpkeepNotNeed(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );
    // enum
    enum LotteryState { OPEN, CALCULATING }

    // struct
    struct Tuple {
        uint8[] numbers;
        uint8[] stars;
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
    address payable[] private s_recentWinners;
    bool s_maxJackpotReachedAndStillNoWinner;
    uint8 s_numberOfDrawsSinceMaxJackpotReached;
    uint256 private s_nbParticipants;
    Tuple[] s_grids;
    address payable[] s_playersAddress;
    address payable[] s_winners;
    // events
    event EnteredLottery(address player);
    event PickedWinners(address payable [] indexed winner);

    // constructor
    constructor(
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit) VRFConsumerBaseV2(vrfCoordinator)
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
     function enterLottery(bool gridState, uint8[][2] memory numbersAndStars) external payable {
        if (s_lotteryState != LotteryState.OPEN)
            revert Lottery__LotteryNotOpen();
        if (gridState) {
            if (msg.value < 50)
                revert Lottery__NotEnoughEthSent();
        }
        else {
            if (msg.value < 25)
                revert Lottery__NotEnoughEthSent();
        }

        if (numbersAndStars.length == 0) 
            revert Lottery__PlayerForgotGrid();

        if (numbersAndStars[0].length != 5 || numbersAndStars[1].length != 2)
            revert Lottery__PlayerInputWrongGridFormat();

        for (uint8 i = 0; i < 2; i++) {
            for (uint8 j = 0; j < numbersAndStars[i].length; j++) {
                if (numbersAndStars[i][j] < 1 || numbersAndStars[0][i] > 50)
                    revert Lottery__PlayerInputWrongGridFormat();
            }
        }
        if (gridState) {
            for (uint8 i = 1; i < 12; i++) {
                for (uint8 j = i + 1; j < 13; j++) {
                    uint8[] memory stars;
                    stars[0] = i;
                    stars[1] = j;
                    s_grids.push(Tuple(numbersAndStars[0], stars));
                }
            }
            s_players[msg.sender] = s_grids;
        }
        else {
            s_grids.push(Tuple(numbersAndStars[0], numbersAndStars[1]));
            s_players[msg.sender] = s_grids;
        }
        s_nbParticipants++;
        s_playersAddress.push(payable(msg.sender));
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
        public
        view override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = s_lotteryState == LotteryState.OPEN;
        bool hasPlayers = s_nbParticipants > 0;
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
            revert Lottery__UpkeepNotNeed(
                address(this).balance,
                s_nbParticipants,
                uint256(s_lotteryState)
            );

        if (block.timestamp - s_lastTimeStamp <= i_interval)
            revert Lottery__NotEnoughTimePassed();
        s_lotteryState = LotteryState.CALCULATING;

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
            uint8 len = (i == 1) ? 2 : 5;
            for (uint8 j = 0; j < len; j++) {
                numbersAndStars[i][j] = uint8(randomWords[i * 5 + j] % 50) + 1;
            }
        }
        address payable[] memory winners;
        if (address(this).balance < MAXIIMUM_JACKPOT)
            winners = pickWinnerBeforeMaxAndFiveDraws(numbersAndStars);
        else{
            if(s_numberOfDrawsSinceMaxJackpotReached == 0)
                s_maxJackpotReachedAndStillNoWinner = true;
            if (s_numberOfDrawsSinceMaxJackpotReached == 5)
                winners = pickWinnerAfterMaxAndFiveDraws(numbersAndStars);
            else {
                s_numberOfDrawsSinceMaxJackpotReached++;
                winners = pickWinnerBeforeMaxAndFiveDraws(numbersAndStars);
                if (winners.length == 0)
                    return;
            }
        }
        s_lotteryState = LotteryState.OPEN;
        s_playersAddress = new address payable[](0);
        s_nbParticipants = 0;
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

    function pickWinnerBeforeMaxAndFiveDraws(uint8[][2] memory numbersAndStars) internal returns (address payable[] storage){
        for (uint256 i = 0; i < s_nbParticipants; i++) {
            Tuple[] memory grids = s_players[s_playersAddress[i]];
            for (uint256 j = 0; j < grids.length; j++) {
                Tuple memory grid = grids[j];
                uint8[] memory numbers = grid.numbers;
                bool valid = true;
                for (uint8 k = 0; k < 5; k++) {
                    if (numbers[k] != numbersAndStars[0][k]) {
                        valid = false;
                        break;
                    }
                }
                if (valid) {
                    uint8[] memory stars = grid.stars;
                    for (uint8 k = 0; k < 2; k++) {
                        if (stars[k] != numbersAndStars[1][k]) {
                            valid = false;
                            break;
                        }
                    }
                    if (valid) {
                        s_winners.push(s_playersAddress[i]);
                    }
                }
            }
        }
        return s_winners;
    }
    function pickWinnerAfterMaxAndFiveDraws(uint8[][2] memory numbersAndStars) internal returns (address payable[] storage){
        uint8 bestScore;
        for (uint256 i = 0; i < s_nbParticipants; i++) {
            Tuple[] memory grids = s_players[s_playersAddress[i]];
            for (uint256 j = 0; j < grids.length; j++) {
                uint8 score;
                Tuple memory grid = grids[j];
                uint8[] memory numbers = grid.numbers;
                for (uint8 k = 0; k < 5; k++) {
                    if (numbers[k] == numbersAndStars[0][k]) {
                        score++;
                    }
                }
                uint8[] memory stars = grid.stars;
                for (uint8 k = 0; k < 2; k++) {
                    if (stars[k] == numbersAndStars[1][k]) {
                        score++;
                    }
                }
                if (score == bestScore) {
                    s_winners.push(s_playersAddress[i]);
                }
                if (score > bestScore) {
                    bestScore = score;
                    s_winners = new address payable[](0);
                    s_winners.push(s_playersAddress[i]);
                }
            }
        }
        return s_winners;
    }

    // Getters
    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function getPlayer(
        uint256 indexOfPlayer
    ) external view returns (address payable) {
        return s_playersAddress[indexOfPlayer];
    }

    function getRecentWinners() external view returns (address payable[] memory){
        return s_recentWinners;
    }
    function getLengthOfPlayers() external view returns (uint256) {
        return s_nbParticipants;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}