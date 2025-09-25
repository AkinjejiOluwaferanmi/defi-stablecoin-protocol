// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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
// view & pure functions

pragma solidity ^0.8.23;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Akinjeji Oluwaferanmi
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////////
    // Errors //
    ///////////////////////
    error DSCEngine__NeedsMoreThanZeroCollateral();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength();
    error DSCEngine__CollateralTokenNotAllowed(address collateralToken);
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOkay();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////////
    // Type //
    ///////////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////////
    // State Variables //
    ///////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // 10 decimals
    uint256 private constant PRECISION = 1e18; // 1 with 18 decimals
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% liquidation threshold
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% liquidation bonus

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposits;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////
    // Events //
    ///////////////////////
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 indexed collateralAmount);

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed collateralToken,
        uint256 amountCollateral
    );

    ///////////////////////
    // Modifiers //
    ///////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZeroCollateral();
        }
        _;
    }

    modifier isAllowedToken(address collateralToken) {
        // Check if the token is allowed
        if (s_priceFeeds[collateralToken] == address(0)) {
            revert DSCEngine__CollateralTokenNotAllowed(collateralToken);
        }
        _;
    }

    ///////////////////////
    // Constructor //
    ///////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // External Functions
    /**
     * @notice Allows users to deposit collateral and mint DSC in one transaction.
     * @param collateralToken The address of the collateral token to deposit.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDscToMint The amount of Decentralized Stable Coin to mint.
     */
    function depositCollateralAndMintDsc(address collateralToken, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        depositCollateral(collateralToken, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Allows users to deposit collateral.
     * @notice Follows CEI pattern (Checks-Effects-Interactions).
     * @param collateralToken The address of the collateral token to deposit.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function depositCollateral(address collateralToken, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(collateralToken)
        nonReentrant
    {
        //Logic to deposit collateral
        s_collateralDeposits[msg.sender][collateralToken] += amountCollateral;
        emit CollateralDeposited(msg.sender, collateralToken, amountCollateral);
        bool succeess = IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral);
        if (!succeess) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param collateralToken The collateral Address to redeem
     * @param amountCollateral The amount collateral to redeem
     * @param amountDscToken The amount of DSC to burn
     * The function burns DSC and redeems underlying collateral in one transaction.
     */
    function redeemCollateralForDsc(address collateralToken, uint256 amountCollateral, uint256 amountDscToken)
        external
    {
        burnDsc(amountDscToken);
        redeemCollateral(collateralToken, amountCollateral);
        // RedeemCollateral already checks health factor.
    }

    // In order to redeem collateral
    // 1. the health factor must be over 1 AFTER the collataral is redeemed
    function redeemCollateral(address collateralToken, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, collateralToken, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Allows users to mint DSC after depositing collateral.
     * @param amountDscToMint The amount of Decentralized to mint.
     * @notice They must have more colleteral value than the minimum threshold.
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        // After burning DSC, we need to check if the health factor is still okay.
        // If the health factor is broken, we need to revert.
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit......
    }

    // If we do start nearing under-collateralization, we can do need someone to liquidate the position.
    // Liquidation is when someone takes the collateral of a user who is under-collateralized and gives them DSC.
    // The liquidator gets a discount on the collateral.
    // Liquidation is a way to incentivize people to keep the system healthy.
    /**
     * @notice Allows users to liquidate under-collateralized accounts.
     * @param collateralAddress The address of the collateral token to liquidate from the user.
     * @param user The address of the user to liquidate. The user who has broken their health factor.
     * Their health factor should be below the minimum threshold.
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor to
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     * Follows CEI pattern (Checks-Effects-Interactions).
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // We need to check health factor of the user.
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOkay();
        }
        // We want to burn their DSC "debt"
        // And take their collateral.
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralAddress, debtToCover);
        // And give them a 10% bonus
        // We should implement a feature to liquidate in the event the protocol is insolvent.
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION);
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralAddress, totalCollateralToRedeem);
        //We need to burn the DSC from the user.
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // Private & Internal View Functions
    /**
     * @dev Low level internal function to burn DSC, do not call unless the function calling it
     * is checking for health factor being broken.
     * @notice This function is used to burn DSC from a specific address.
     * @notice It is private because it is only used internally in the contract.
     * @param amountDscToBurn The amount of DSC to burn.
     * @param onBehalfOf The address of the user who is burning the DSC.
     * @param dscFrom Address from which the DSC is being burned.
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address collateralToken, uint256 amountCollateral) private {
        s_collateralDeposits[from][collateralToken] -= amountCollateral;
        emit CollateralRedeemed(from, to, collateralToken, amountCollateral);
        bool success = IERC20(collateralToken).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * Returns how close to liqidation a user is.
     * A health factor of 1 means the user is at the minimum threshold.
     * A health factor below 1 means the user can get liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Get total collateral value
        // Get total DSC minted
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // Internal Functions

    // Check Health Factor
    // Revert if health factor is broken
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken(userhealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedforThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedforThreshold * 1e18) / totalDscMinted;
    }

    // Getter Functions
    function getTokenAmountFromUsd(address token, uint256 usdamountInWei) public view returns (uint256) {
        //Price of the token in USD
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdamountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token, get the amount of collateral deposited, and the price of the collateral token.
        // And map it to price to get the USD value.
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposits[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amountCollateral);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposits[user][token];
    }
}
