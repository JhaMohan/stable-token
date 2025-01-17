// SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Aditya Mohan
 * @notice This library is used to check the chainlink Oracle for stale data.
 * If a price is a stale,the function will revert, and render the DSCEngine unusable - this is by design,
 * 
 * 
 * We want the DSCEngine to freeze if price become stale.
 * 
 * So if chainlink network explodes and you have a lot money locked in protocol... to bad
 * 
 */
library OracleLib {

  error OracleLib__StalePrice();

  uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60

  function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80,int256,uint256,uint256,uint80) {
    (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
    uint256 secondSince = block.timestamp - updatedAt;
    if(secondSince > TIMEOUT) revert OracleLib__StalePrice();

    return (roundId,answer,startedAt,updatedAt,answeredInRound);
  }
  
}