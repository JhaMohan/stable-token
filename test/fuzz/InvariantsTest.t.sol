// SPDX-License-Identifier:MIT

// Have our invariants aka properties

// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view funciton should never revert <-- evergreen invariant

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 wethAmountDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 wbtcAmountDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 totalDsc = dsc.totalSupply();

        uint256 wethValue = dscEngine.getUsdValue(weth, wethAmountDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, wbtcAmountDeposited);

        console.log("weth value: ",wethValue);
        console.log("wbtc value: ",wbtcValue);
        console.log("total value: ",totalDsc);
        console.log("mint called:" ,handler.timesMintIsCalled());
        console.log("depositCollateral called: ",handler.timesDepositeCollateralCalled());
        console.log("timesRedeemCollateralCalled: ",handler.timesRedeemCollateralCalled());
        console.log("updateCollateralPriceCalled: ",handler.updateCollateralPriceCalled());

        assert(wethValue + wbtcValue >= totalDsc);
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getLiquidationBonus();
        dscEngine.getPrecision();
    }
}
