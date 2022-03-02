// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract PriceConsumerV3 {
  AggregatorV3Interface internal priceFeedEthUsd;
  AggregatorV3Interface internal priceFeedEurUsd;

  int256 private ethUsdPriceFake = 2000 * 10 ** 8; // remember to divide by 10 ** 8

  // 1.181
  int256 private eurUsdPriceFake = 1181 * 10 ** 5; // remember to divide by 10 ** 8

  constructor() {
  }

  /**
   * Returns the latest price of ETH / USD
   */
  function getThePriceEthUsd() public view returns (int256) {
    if (
      block.chainid == 1 ||
      block.chainid == 42 ||
      block.chainid == 137 ||
      block.chainid == 80001
    ) {
      (, int256 price, , , ) = priceFeedEthUsd.latestRoundData();
      return price;
    } else {
      return ethUsdPriceFake;
    }
  }

  /**
   * Returns the latest price of EUR / USD
   */
  function getThePriceEurUsd() public view returns (int256) {
    if (
      block.chainid == 1 ||
      block.chainid == 42 ||
      block.chainid == 137
    ) {
      (, int256 price, , , ) = priceFeedEurUsd.latestRoundData();
      return price;
    } else {
      return eurUsdPriceFake;
    }
  }
}
