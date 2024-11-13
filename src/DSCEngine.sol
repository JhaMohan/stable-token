//SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// interfaces, libraries, contracts
// imports
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

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

// DSC(Decentralized Stable Token)
/**
 * @title DSCEngine
 * @author Aditya
 *
 * The system is designed as mininmal as possible, and have the tokens maintain  1 token == 1$ peg.
 *
 * This stablecoin has the properties:
 *  - Exogenous Collateral
 *  - Dollar pegged
 *  - Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance , no fees and only backed by wETH and wBTC.
 *
 * Our DSC system should always be "overcollaterlized". At no point, should the value of
 * all collateral <= the $ backed value of all DSC.
 *
 * @notice This contract is the core of the DSC system. It handels all the logic for minting and redeeming DSC,
 * as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                               Error
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImporved();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                               State Variables
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenPriceFeed
    DecentralizedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    /*//////////////////////////////////////////////////////////////
                               Events
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed collateralRedeemFrom, address indexed collateralRedeemTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                               Modifiers
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // For Example ETH/USD ,BTC/USD,MKR/USD,
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *
     * @param tokenCollateralAddress - The address of the token to deposit as collateral
     * @param amountCollateral - The amount of collateral to deposit
     * @param amountDscToMint - The amount of decentralized stable coin to mint
     * @notice this function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follw CEI (check(modifier) ,effect(updating amount) ,interaction() )
     * @param tokenCollateralAddress - The address of the token to deposit as collateral
     * @param amountCollateral - The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isTokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * This function will burn DSC and redeem underlying collateral in one transaction
     * @param tokenCollateralAddress - The address of the collateral token
     * @param amountToRedeem - The collateral amount wants to redeem
     * @param amountDscToBurn - The amount to burn in the DSC
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountToRedeem, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountToRedeem);
        // we don't need to check for healthFactor as that is already done in redeemCollateral()
    }

    // in order to redeem collateral:
    // 1. Health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountToRedeem)
        public
        moreThanZero(amountToRedeem)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountToRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follow CEI
     * @param amountDscToMint - amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much ($150 DSC , $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // we don't need this
    }

    /**
     *
     * @param tokenCollateralAddress - The erc20 collateral address to liquidate from the user
     * @param user - The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover - The amount of DSC you want to burn to improve the health factor.
     * @notice You can partially liquidate the user.
     * @notice You will get a liquidation bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators.
     * For example, if the price of collateral plummeted before anyone could be liquidated.
     *
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor > MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //we want to burn their DSC "debt"
        // And take their collateral
        // Bad User: $140 ETH , $100 DSC
        // debtToCover = $100
        // $100 of DSC === ? ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amount into a treasury
        uint256 bonusCollateral = ((tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION);

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);
        // now we need to burn DSC
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImporved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                       PRIVATE  & INTERNAL FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev low-level internal function,do not call unless function calling this should check for health factor being broken
     */
    function _burnDsc(uint256 amountToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountToBurn;
        bool success = IERC20(i_dsc).transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountToRedeem, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountToRedeem;
        emit CollateralRedeemed(msg.sender, to, tokenCollateralAddress, amountToRedeem);

        bool sucess = IERC20(tokenCollateralAddress).transfer(to, amountToRedeem);

        if (!sucess) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateral(user);
    }

    /**
     *
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC Minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    // 1. Check health factor (do they have enough collateral)?
    // 2. revert if hey don't

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // $150 collateral / 100 DSC =1.5
        // 150*50 = 7500/100 = 75 = (75/100) < 1

        // $1000 collateral / 100 DSC
        // 1000 * 50 = 5000 /100 = 500 = (50/100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL & PUBLIC VIEW & PURE FUNTION
    //////////////////////////////////////////////////////////////*/

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address collateral, uint256 usdAmountInWei) public view returns (uint256) {
        // Price of ETH (token)
        // $/ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateral]);
        (, int256 answer,,,) = priceFeed.staleCheckLatestRoundData();
        // (10e18 * 1e18)/(2000*1e8*1e10)

        return ((usdAmountInWei * PRECISION) / (uint256(answer) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateral(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token,get the amount they have deposited and map it to price ,to ge USD value

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 answer,,,) = priceFeed.staleCheckLatestRoundData();

        //1 ETH = $1000
        // The returned value from CL will be 1000 *1e8
        return (((uint256(answer) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION); // ((1000*1e8)*1e10)
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        (totalDscMinted, totalCollateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
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

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
