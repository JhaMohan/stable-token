//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 50 ether;
    uint256 public constant INITIAL_ERC20_BALANCE = 50 ether;
    uint256 public constant DSC_MINT_AMOUNT = 5 ether;
    uint256 public constant DSC_BURN_AMOUNT = 2 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, INITIAL_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TEST
    //////////////////////////////////////////////////////////////*/
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE TEST
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 amount = 30e18;
        uint256 expectedAmount = 60000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, amount);
        assert(expectedAmount == usdValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmountInWei = 4000 ether;
        uint256 expectedAmount = 2 ether;

        vm.prank(USER);
        uint256 actualAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmountInWei);
        assertEq(expectedAmount, actualAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TEST
    //////////////////////////////////////////////////////////////*/
    function testRevertIfCollateralZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertIfInvalidCollateral() public {
        ERC20Mock rawToken = new ERC20Mock("RAW", "RAW", USER, INITIAL_ERC20_BALANCE);

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(rawToken), AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dscEngine.getAccountCollateral(USER);

        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(totalCollateralValueInUsd, expectedCollateralValueInUsd);
    }

    /*//////////////////////////////////////////////////////////////
                             HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/

    function testHealthFactor() public {
        vm.prank(USER);
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);
        uint256 expectedHealthFactor = type(uint256).max;
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/

    function testRevertIfMintAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dscEngine.mintDsc(DSC_MINT_AMOUNT);
        vm.stopPrank();
    }

    function testMintDscIfEnoughCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(DSC_MINT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                BURN DSC
    //////////////////////////////////////////////////////////////*/
    function testRevertIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscIfHealthFactorNotBroke() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(DSC_MINT_AMOUNT);
        dsc.approve(address(dscEngine), DSC_BURN_AMOUNT);
        dscEngine.burnDsc(DSC_BURN_AMOUNT);
        vm.stopPrank();
    }
}
