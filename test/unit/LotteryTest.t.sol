// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployLottery} from "../../script/DeployLottery.s.sol";
import {Lottery} from "../../src/Lottery.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";
contract LotteryTest is StdCheats, Test {
    // Events
    event RequestedlotteryWinner(uint256 indexed requestId);
    event Enteredlottery(address indexed player);
    event WinnerPicked(address indexed player);
    Lottery public lottery;
    HelperConfig public helperConfig;

    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployLottery deployer = new DeployLottery();
        (lottery, helperConfig) = deployer.run();
        (
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testlotteryInitializesInOpenState() external {
        assert(lottery.getLotteryState() == Lottery.LotteryState.OPEN);
    }

    // enterlottery
    function testlotteryRecordsPlayerWhenTheyEnter() external {
        // Arrange
        vm.prank(PLAYER);
        // Act
        lottery.enterLottery{value: 25 ether}();
        address playerRecorded = lottery.getPlayer(0);
        // Assert
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(lottery));
        emit Enteredlottery(PLAYER);
        lottery.enterLottery{value: 25 ether}();
    }

    function testCantEnterWhenlotteryIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        lottery.enterlottery{value: 25 ether}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpkeep("");
        vm.expectRevert(lottery.Lottery__LotteryNotOpen.selector);
        vm.prank(PLAYER);
        lottery.enterlottery{value: 25 ether}();
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded,) = lottery.checkUpkeep("");

        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIflotteryNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        lottery.enterLottery{value: 25 ether}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpkeep("");
        Lottery.LotteryState lotteryState = lottery.getLotteryState();
        // Act
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");
        // Assert
        assert(lotteryState == lottery.lotteryState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed() public {
       // Arrange
        vm.prank(PLAYER);
        lottery.enterLottery{value: 25 ether}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }
    function testCheckUpKeepReturnsTrueWhenParametersAreGood() public {
        // Arrange
        vm.prank(PLAYER);
        lottery.enterLottery{value: 25 ether}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        lottery.enterLottery{value: 25 ether}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        lottery.performUpkeep("");
    }

    function testPerformUpKeepRevertsIfCheckUpKeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Lottery.LotteryState lotteryState = lottery.getlotteryState();

        // Act/Assert
        vm.expectRevert(abi.encodeWithSelector(lottery.Lottery__UpkeepNotNeed.selector, currentBalance, numPlayers, lotteryState));
        lottery.performUpkeep("");
    }
    // what if I need to test using the output of an event

    modifier lotteryEnteredandTimePassed {
        vm.prank(PLAYER);
        lottery.enterlottery{value: 25 ether}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpKeepUpdateslotteryStateAndEmitsRequestId() public lotteryEnteredandTimePassed {
        // Arrange
        vm.expectEmit(true, false, false, false, address(lottery));
        // Act
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Lottery.LotteryState lotteryState = lottery.getLotteryState();
        // Assert
        assert(uint256(requestId) > 0);
        assert(uint256(lotteryState) == 1);
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }
    function testFulFillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public lotteryEnteredandTimePassed skipFork {
        // Arrange/Act
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(lottery));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public lotteryEnteredandTimePassed skipFork {
        // Arrange
        uint256 startingIndex = 1;
        uint256 additionalEntrants = 5;
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            hoax(address(uint160(i)), 1 ether);
            lottery.enterlottery{value: 25 ether}();
        }
        uint256 prize = 25 ether * (additionalEntrants + 1);
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 previousTimestamp = lottery.getLastTimeStamp();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        // Assert
        assert(lottery.getlotteryState() == lottery.lotteryState.OPEN);
        assert(lottery.getRecentWinner() != address(0));
        assert(lottery.getLengthOfPlayers() == 0);
        assert(lottery.getLastTimeStamp() > previousTimestamp);
        assert(lottery.getRecentWinner().balance == STARTING_USER_BALANCE + prize - 25 ether);
    }
}
