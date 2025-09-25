// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSCEngine} from "script/DeployDSCEngine.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    error DSCEngine__NeedsMoreThanZeroCollateral();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength();
    error DSCEngine__CollateralTokenNotAllowed(address tokenCollateralAddress);
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOkay();
    error DSCEngine__HealthFactorNotImproved();

    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed collateralAmount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    DeployDSCEngine public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address wethAddress;
    address wbtcAddress;

    address[] public tokenAddresses;
    address[] public priceFeeds;

    uint256 public userHealthFactor;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant REDEEMED_COLLATERAL = 3e17; // Equivalent to 0.3 ether
    uint256 public constant AMOUNT_TO_MINT = 500e18;
    uint256 public constant AMOUNT_TO_BURN = 100e18;
    uint256 public constant ZERO = 0;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, wethAddress, wbtcAddress,) = config.activeNetworkConfig();
        ERC20Mock(wethAddress).mint(USER, AMOUNT_COLLATERAL);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function testRevertsIfTokenAddressesAndPriceFeedAddressesNotEqualLength() public {
        // Arrange
        tokenAddresses.push(wethAddress);
        tokenAddresses.push(wbtcAddress);
        priceFeeds.push(ethUsdPriceFeed);

        // Act & Assert
        vm.expectRevert(DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength.selector);
        new DSCEngine(tokenAddresses, priceFeeds, address(dsc));
    }

    function testCollateralTokensAreCorrect() public {
        // Arrange
        tokenAddresses.push(wethAddress);
        tokenAddresses.push(wbtcAddress);

        assertEq(tokenAddresses, dscEngine.getCollateralTokens());
    }

    function testCollateralTokensPriceFeedsAreCorrect() public view {
        assertEq(dscEngine.getCollateralTokenPriceFeed(wethAddress), ethUsdPriceFeed);
        assertEq(dscEngine.getCollateralTokenPriceFeed(wbtcAddress), btcUsdPriceFeed);
    }

    //////////////////
    // Price Tests //
    //////////////////
    function testUsdValue() public view {
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsd = 30000e18; // Assuming ETH price is $2000
        uint256 actualUsdValue = dscEngine.getUsdValue(wethAddress, ethAmount);
        assertEq(actualUsdValue, expectedUsd, "USD value calculation is incorrect");
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether; // Assuming ETH price is $2000
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(wethAddress, usdAmount);
        assertEq(actualWeth, expectedWeth, "Token amount from USD calculation is incorrect");
    }

    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine__NeedsMoreThanZeroCollateral.selector);
        dscEngine.depositCollateral(wethAddress, ZERO);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedAmount = dscEngine.getTokenAmountFromUsd(wethAddress, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    function testRevertsWithCollateralTokenNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock("Random Token", "RAT", USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine__CollateralTokenNotAllowed.selector, address(randomToken)));
        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testEmitCollateralDeposited() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, wethAddress, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine__TransferFailed.selector);
        vm.mockCall(
            wethAddress,
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(dscEngine), AMOUNT_COLLATERAL),
            abi.encode(false)
        );
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    ///////////////////////////////////////
    // Mint Functions //
    ///////////////////////////////////////
    function testDscMintedSuccessfully() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_TO_MINT);
        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT);
    }
    
    function testDscMintedRevertsIfMintedZeroDsc() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine__NeedsMoreThanZeroCollateral.selector);
        dscEngine.mintDsc(ZERO);
    }

    function testRevertsMintFailed() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine__MintFailed.selector);
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(DecentralizedStableCoin.mint.selector, USER, AMOUNT_TO_MINT),
            abi.encode(false)
        );
        dscEngine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // Deposit Collateral and Mint Functions //
    ///////////////////////////////////////
    function testCollateralDepositedAndDscMintedFunction() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);

        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        uint256 amountToMint;
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision()));
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(wethAddress, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // Burn Functions //
    ///////////////////////////////////////
    function testBurnDscFucntion() public depositedCollateral {
        uint256 finalDscValue = 400e18;

        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_TO_MINT);

        dsc.approve(address(dscEngine), AMOUNT_TO_BURN);
        dscEngine.burnDsc(AMOUNT_TO_BURN);

        assertEq(dsc.balanceOf(USER), finalDscValue);
        vm.stopPrank();
    }

    function testRevertsIfBurnFunctionFails() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_BURN);

        vm.expectRevert(DSCEngine__TransferFailed.selector);
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(USER), address(dscEngine), AMOUNT_TO_BURN),
            abi.encode(false)
        );
        dscEngine.burnDsc(AMOUNT_TO_BURN);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // Redeem Collateral //
    ///////////////////////////////////////
    function testRedeemCollateral() public depositedCollateralAndMintedDsc {
        uint256 finalCollateralValue = 3e17;

        vm.startPrank(USER);
        dscEngine.redeemCollateral(wethAddress, REDEEMED_COLLATERAL);
        vm.stopPrank();

        assertEq(IERC20(wethAddress).balanceOf(USER), finalCollateralValue);
        assertEq(dscEngine.getCollateralBalanceOfUser(USER, wethAddress), 7e17);
    }

    function testEmitRedeemedCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, wethAddress, REDEEMED_COLLATERAL);
        dscEngine.redeemCollateral(wethAddress, REDEEMED_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        uint256 finalCollateralValue = 3e17;
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.redeemCollateralForDsc(wethAddress, REDEEMED_COLLATERAL, AMOUNT_TO_BURN);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 400e18);
        assertEq(IERC20(wethAddress).balanceOf(USER), finalCollateralValue);
    }

    function testRevertsIfDscToBurnIsZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine__NeedsMoreThanZeroCollateral.selector);
        dscEngine.redeemCollateralForDsc(wethAddress, 20 ether, 0);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // Liquidate Section //
    ///////////////////////////////////////
    function testRevertsHealthFactorIsOkay() public depositedCollateralAndMintedDsc {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine__HealthFactorIsOkay.selector);
        dscEngine.liquidate(wethAddress, USER, AMOUNT_TO_BURN);
        vm.stopPrank();
    }

    function testLiquidationWorks() public depositedCollateralAndMintedDsc {
        // Drop the ETH price from $2000 to $900
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8);

        // We want to assert that the health Factor of the user is lesser than 1.0 - Min Health Factor
        assertLt(dscEngine.getHealthFactor(USER), dscEngine.getMinHealthFactor());

        vm.startPrank(LIQUIDATOR);
        deal(wethAddress, LIQUIDATOR, 5 ether);
        ERC20Mock(wethAddress).approve(address(dscEngine), 3 ether);
        dscEngine.depositCollateralAndMintDsc(wethAddress, 3 ether, 1000e18);

        IERC20(dsc).approve(address(dscEngine), 200e18);
        dscEngine.liquidate(wethAddress, USER, 200e18);
        vm.stopPrank();

        assertGt(dscEngine.getHealthFactor(USER), dscEngine.getMinHealthFactor());
    }

    function testHealthFactor() public depositedCollateralAndMintedDsc {
        assertEq(dscEngine.getHealthFactor(USER), 2e18);
    }

    /* function testRevertsHealthFactorHasNotImproved() public {
        // Since user has 1 WETH that has been minted in the setUp I don't need to give him WETH.
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, 1000e18);
        vm.stopPrank();

        // Drop the ETH price from $2000 to $900
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(500e8);

        // We want to assert that the health Factor of the user is lesser than 1.0 - Min Health Factor
        assertLt(dscEngine.getHealthFactor(USER), dscEngine.getMinimumHealthFactor());

        deal(wethAddress, LIQUIDATOR, 10 ether);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wethAddress).approve(address(dscEngine), 3 ether);
        dscEngine.depositCollateralAndMintDsc(wethAddress, 3 ether, 1000e18);

        IERC20(dsc).approve(address(dscEngine), 10e18);
        vm.expectRevert(DSCEngine__HealthFactorNotImproved.selector);
        dscEngine.liquidate(wethAddress, USER, 10e18);
        vm.stopPrank();
    } */

    ///////////////////////////////////////
    // Getter Functions  //
    ///////////////////////////////////////
    function testGetCollateralValueInUsd() public depositedCollateral {
        uint256 testFunctionCollateralValueInUsd = 2000e18;
        uint256 actualCollateralValueInUsd = dscEngine.getAccountCollateralValueInUsd(USER);
        assertEq(dscEngine.getAccountCollateralValueInUsd(USER), testFunctionCollateralValueInUsd);
        assertEq(actualCollateralValueInUsd, testFunctionCollateralValueInUsd);
    }

    function testGetDscHelperFunctionIsAccurate() public view {
        assertEq(address(dsc), dscEngine.getDsc());
    }

    function testPrecision() public view {
        assertEq(dscEngine.getPrecision(), 1e18);
    }

    function testLiquidationBonus() public view {
        assertEq(dscEngine.getLiquidationBonus(), 10);
    }

    function testLiquidationPrecision() public view {
        assertEq(dscEngine.getLiquidationPrecision(), 100);
    }

    function testLiqidationThreshold() public view {
        assertEq(dscEngine.getLiquidationThreshold(), 50);
    }
}
