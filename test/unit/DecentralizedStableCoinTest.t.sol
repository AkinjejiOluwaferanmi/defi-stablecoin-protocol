// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDecentralizedStableCoin} from "script/DeployDecentralizedStableCoin.s.sol";

contract DecentralizedStableCoinTest is Test {
    error DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__CantMintToZeroAddress();
    error DecentralizedStableCoin__AmountMustBeGreaterThanZero();

    DecentralizedStableCoin public decentralizedStableCoin;
    DeployDecentralizedStableCoin public deployer;

    address JOHN = makeAddr("john");
    uint256 public constant STARTING_BALANCE = 5 ether;
    uint256 public constant TEST_AMOUNT = 10;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        decentralizedStableCoin = deployer.run();
    }

    function testStableCoinName() public view {
        string memory expectedName = "DecentralizedStableCoin";
        assertEq(keccak256(abi.encode(decentralizedStableCoin.name())), keccak256(abi.encode(expectedName)));
    }

    function testCantMintToZeroAddress() public {
        // Arrange
        address zeroAddress = address(0);

        // Act & Assert
        vm.startPrank(decentralizedStableCoin.owner());
        vm.expectRevert(DecentralizedStableCoin__CantMintToZeroAddress.selector);
        decentralizedStableCoin.mint(zeroAddress, TEST_AMOUNT);
    }

    function testAmountMustBeGreaterThanZero() public {
        // Act & Assert
        vm.startPrank(decentralizedStableCoin.owner());
        vm.expectRevert(DecentralizedStableCoin__AmountMustBeGreaterThanZero.selector);
        decentralizedStableCoin.mint(JOHN, 0);
    }

    function testBurnAmountMustBeGreaterThanZero() public {
        // Act & Assert
        vm.startPrank(decentralizedStableCoin.owner());
        vm.expectRevert(DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero.selector);
        decentralizedStableCoin.burn(0);
    }

    function testBurnAmountExceedsBalance() public {
        //Arrange
        vm.deal(decentralizedStableCoin.owner(), STARTING_BALANCE);

        // Act & Assert
        vm.startPrank(decentralizedStableCoin.owner());
        vm.expectRevert(DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        decentralizedStableCoin.burn(TEST_AMOUNT);
    }

    function testDscHasBeenMinted() public {
        // Act & Assert
        vm.startPrank(decentralizedStableCoin.owner());
        bool success = decentralizedStableCoin.mint(JOHN, TEST_AMOUNT);
        require(success, "Dsc has not been minted!");
    }

    function testDscHasBeenBurned() public {
        vm.deal(decentralizedStableCoin.owner(), 100 ether);
        uint256 AMOUNT = 5;

        vm.startPrank(decentralizedStableCoin.owner());
        decentralizedStableCoin.mint(decentralizedStableCoin.owner(), TEST_AMOUNT);
        uint256 initialSupply = decentralizedStableCoin.totalSupply();

        decentralizedStableCoin.burn(AMOUNT);
        uint256 finalSupply = decentralizedStableCoin.totalSupply();

        assertEq(finalSupply, initialSupply - AMOUNT);
    }
}
