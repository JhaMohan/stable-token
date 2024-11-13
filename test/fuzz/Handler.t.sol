// SPDX-License-Identifier:MIT

// Handler is going to narrow down the way we call function

pragma solidity ^0.8.19;

import {Test,console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    address[] private accountDepositedToken;

    uint256 public timesMintIsCalled;
    uint256 public timesDepositeCollateralCalled;
    uint256 public timesRedeemCollateralCalled;
        uint256 public updateCollateralPriceCalled;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralToken = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralToken[0]);
        wbtc = ERC20Mock(collateralToken[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function mintDsc(uint256 amount,uint256 addressSeed) public {
        if(accountDepositedToken.length ==0) {return;}
        address sender = accountDepositedToken[addressSeed % accountDepositedToken.length];
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxTokenMint = (int256(totalCollateralValueInUsd)/2) - int256(totalDscMinted);
        console.log("maxTokenMint: ",maxTokenMint);
        if(maxTokenMint < 0 ) {return;}
        amount = bound(amount,0,uint256(maxTokenMint));
        if(amount == 0) {return;}
        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 depositCollateralSeed, uint256 amountToDeposit) public {
        ERC20Mock depositCollateralToken = _getCollateralFromSeed(depositCollateralSeed);
        amountToDeposit = bound(amountToDeposit, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        depositCollateralToken.mint(msg.sender, amountToDeposit);
        depositCollateralToken.approve(address(dscEngine), amountToDeposit);
        dscEngine.depositCollateral(address(depositCollateralToken), amountToDeposit);
        vm.stopPrank();
        accountDepositedToken.push(msg.sender);
        timesDepositeCollateralCalled++;
    }

    function redeemCollateral(uint256 redeemCollateralSeed, uint256 amountToRedeem) public {
        ERC20Mock redeemCollateralToken = _getCollateralFromSeed(redeemCollateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(redeemCollateralToken));
        amountToRedeem = bound(amountToRedeem, 0, maxCollateralToRedeem);
        console.log("amountToRedeem:",amountToRedeem);
        if (amountToRedeem == 0) {
            return;
        }
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(redeemCollateralToken), amountToRedeem);
        timesRedeemCollateralCalled++;
    }

    // This will break our invariant test suit
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    //     updateCollateralPriceCalled++;
    // }

    function _getCollateralFromSeed(uint256 depositCollateralSeed) internal view returns (ERC20Mock) {
        if (depositCollateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
