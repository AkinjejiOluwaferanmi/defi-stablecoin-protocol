// SPDX-License-Identifier: MIT

// This file will have our invariants i.e properties that should always hold true.

// What are our invariants?
// 1. The total supply of DSC should always be less than or equal to the total value of collateral.
// 2. Our Getter View functions should never revert.

pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSCEngine} from "script/DeployDSCEngine.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSCEngine deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address wethAddress;
    address wbtcAddress;

    function setUp() external {
        // Set up the invariants we want to test.
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run();
        (,, wethAddress, wbtcAddress,) = config.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get value of all the collateral in the protocol
        // Compare it to all the total supply of DSC (Debt)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(wethAddress).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtcAddress).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(wethAddress, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtcAddress, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);
        console.log("Times mint called", handler.timesMintIsCalled());

        assertGe(
            wethValue + wbtcValue,
            totalSupply,
            "Total value of collateral must be greater than or equal to total supply of DSC"
        );
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationPrecision();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getPrecision();
        // dscEngine.getCollateralTokenPriceFeed();
        // dscEngine.getCollateralBalanceOfUser();
        // dscEngine.getHealthFactor();
        // dscEngine.getAccountInformation();
        // dscEngine.getAccountCollateralValueInUsd();
        // dscEngine.getTokenAmountFromUsd();
        // dscEngine.getUsdValue();
    }
}
