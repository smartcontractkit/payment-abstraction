// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {MockUniswapQuoterV2} from "test/mocks/MockUniswapQuoterV2.sol";
import {MockUniswapRouter} from "test/mocks/MockUniswapRouter.sol";

import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

/// @title This contract is used to test the invariants of the SwapAutomator contract
/// Functions exposed to the fuzzer:
/// - performUpkeep
contract UpkeepHandler is BaseTest {
  using PercentageMath for uint256;

  /// @notice This struct contains the parameters required to fuzz the performUpkeep function
  struct UpkeepParams {
    /// @notice The index of the asset in the allowlisted assets array - bound between 0 and the
    /// length of the array
    uint8 assetIndex;
    /// @notice The amount of the asset to swap - bound between its minimum swap size corresponding
    /// value and the AMOUNT_VALUE_UPPER_BOUND
    uint256 amount;
    /// @notice The price of the asset in USD 8 decimals - bound between 1 and 10_000_000e8
    uint256 price;
    /// @notice The amount of LINK to receive after swapping the asset - bound between +/- 5% of the
    /// amountOutMinimum
    uint256 amountOut;
    /// @notice The amount of LINK to receive from UniswapQuoter - bound between +/- 2.5% of the
    /// amountOutFromFeed
    uint256 amountOutFromQuoter;
  }

  /// @notice The upper bound for the amount value - $1M
  uint256 private constant AMOUNT_VALUE_UPPER_BOUND = 100e14;
  /// @notice The maximum LINK token price - $10K
  uint256 private constant MAX_LINK_PRICE = 10_000e8;
  /// @notice The maximum slippage variation of a swap +/- 5%
  uint16 private constant MAX_PRICE_IMPACT = 500;
  address private constant AUTOMATION_SIMULATION_ADDRESS = address(0);

  FeeAggregator private s_feeAggregator;
  SwapAutomator private s_swapAutomator;
  MockUniswapRouter private s_mockUniswapRouter;
  MockUniswapQuoterV2 private s_mockUniswapQuoterV2;
  MockAggregatorV3 private s_mockLinkUsdFeed;
  MockERC20 private s_mockLink;

  /// @notice The addition of all amoutOutMinimums for each performUpkeep call which will be use to
  /// test the invariant
  uint256 private s_totalAmountOutMinimum;

  /// @notice The mapping of assets that have already been fuzzed
  mapping(address asset => bool hasBeenUsed) private s_fuzzedAssets;

  constructor(
    FeeAggregator feeAggregator,
    SwapAutomator swapAutomator,
    MockUniswapRouter mockUniswapRouter,
    MockUniswapQuoterV2 mockUniswapQuoterV2,
    MockAggregatorV3 mockLinkUsdFeed,
    MockERC20 mockLink
  ) {
    s_feeAggregator = feeAggregator;
    s_swapAutomator = swapAutomator;
    s_mockUniswapRouter = mockUniswapRouter;
    s_mockLinkUsdFeed = mockLinkUsdFeed;
    s_mockUniswapQuoterV2 = mockUniswapQuoterV2;
    s_mockLink = mockLink;
  }

  /// @notice Fuzzes the performUpkeep function
  /// @param params Fixed size array of length 3 of the parameters required to fuzz the
  /// performUpkeep function. We use a fixed size array here to reduce execution time and also
  /// because we only allowlist 3 assets in the `Invariant.t.sol` file
  /// @param linkPrice The price of LINK in USD 8 decimals - bound between 1 and 10_000e8
  function performUpkeep(UpkeepParams[3] memory params, uint256 linkPrice) public {
    address[] memory allowlistedAssets = s_feeAggregator.getAllowlistedAssets();
    // Bound link price between 1 and 10_000e8
    linkPrice = bound(linkPrice, 1, 10_000e8);

    // Transmit the link price to the mock LINK/USD feed
    s_mockLinkUsdFeed.transmit(int256(linkPrice));

    uint256 totalAmountOutMinimum;
    uint256 recipientBalanceBefore = s_mockLink.balanceOf(i_receiver);
    bool success;

    for (uint256 i; i < params.length; ++i) {
      UpkeepParams memory upkeepParams = params[i];
      // Bound asset index between 0 and the length of the allowlisted assets array
      upkeepParams.assetIndex = uint8(bound(upkeepParams.assetIndex, 0, allowlistedAssets.length - 1));
      address asset = allowlistedAssets[upkeepParams.assetIndex];

      // If the asset has already been fuzzed, skip it
      if (s_fuzzedAssets[asset]) {
        continue;
      }

      SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(asset);

      // Bound asset price between 1 and 10_000_000e8
      upkeepParams.price = bound(upkeepParams.price, 1, MAX_LINK_PRICE);

      // Transmit the asset price to the mock asset usd feed
      MockAggregatorV3(address(swapParams.usdFeed)).transmit(int256(upkeepParams.price));
      uint256 assetPrice = _getAssetPrice(swapParams.usdFeed);
      uint256 assetUnit = 10 ** IERC20Metadata(asset).decimals();

      // Bound amount to swap between its minimum swap size corresponding value and the upper bound
      // value
      upkeepParams.amount = bound(
        upkeepParams.amount,
        (swapParams.minSwapSizeUsd * assetUnit) / assetPrice + 1,
        (AMOUNT_VALUE_UPPER_BOUND * 10 ** (IERC20Metadata(asset).decimals())) / upkeepParams.price
      );

      // Calculate the amountOutMinimum
      uint256 assetUsdValue = upkeepParams.amount * upkeepParams.price;
      uint256 swapAmount = Math.min(swapParams.maxSwapSizeUsd * assetUnit, assetUsdValue) / assetPrice;

      uint256 amountOutFromFeed =
        _convertToLink(swapAmount, IERC20Metadata(asset), AggregatorV3Interface(swapParams.usdFeed));
      uint256 amountOutFeedWithSlippage =
        amountOutFromFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - swapParams.maxSlippage);

      // Bound amountOutFromQuoter between +/- 2.5% of the amountOutFromFeed
      upkeepParams.amountOutFromQuoter = bound(
        upkeepParams.amountOutFromQuoter,
        amountOutFromFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_PRICE_IMPACT / 2),
        amountOutFromFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR + MAX_PRICE_IMPACT / 2)
      );
      s_mockUniswapQuoterV2.setAssetQuoterAmountOut(asset, upkeepParams.amountOutFromQuoter);

      // Bound amountOut between +/- 5% of the amountOutMinimum
      uint256 amountOutMinimum = Math.max(upkeepParams.amountOutFromQuoter, amountOutFromFeed).percentMul(
        PercentageMath.PERCENTAGE_FACTOR - swapParams.maxSlippage
      );
      upkeepParams.amountOut = bound(
        upkeepParams.amountOut,
        amountOutMinimum.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_PRICE_IMPACT),
        amountOutMinimum.percentMul(PercentageMath.PERCENTAGE_FACTOR + MAX_PRICE_IMPACT)
      );

      uint256 minPostSwapAmount =
        amountOutFromFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - swapParams.maxPriceDeviation);
      // When amountOutUniswapQuoter is less than amountOutFeedWithSlippage, checkUpKeep will
      // exclude this asset.
      if (upkeepParams.amountOutFromQuoter >= amountOutFeedWithSlippage) {
        if (upkeepParams.amountOut >= amountOutMinimum && upkeepParams.amountOut >= minPostSwapAmount) {
          // If the amountOut is greater or equal than both amountOutMinimum and minPostSwapAmount,
          // the performUpkeep call should not revert so we set success to true
          if (!success) success = true;
          // Since the swap in successful we add the amountOutMinimum to the totalAmountOutMinimum
          totalAmountOutMinimum += amountOutMinimum;
        }

        // Deal the amount ouf asset to swap to the FeeAggregator contract
        deal(asset, address(s_feeAggregator), upkeepParams.amount);

        // Set the amountOut of the swap for the asset on the MckUniswapRouter contract
        s_mockUniswapRouter.setAmountOut(asset, upkeepParams.amountOut);
      }

      // Mark the asset as fuzzed
      s_fuzzedAssets[asset] = true;
    }

    // Changing the msg.sender and tx.origin to simulation add since checkUpKeep() is cannotExecute
    _changePrank(AUTOMATION_SIMULATION_ADDRESS, AUTOMATION_SIMULATION_ADDRESS);
    (bool shouldPerformUpkeep, bytes memory data) = s_swapAutomator.checkUpkeep("");
    _changePrank(address(this));

    if (shouldPerformUpkeep) {
      if (!success) {
        vm.expectRevert(SwapAutomator.AllSwapsFailed.selector);
      }

      s_totalAmountOutMinimum += totalAmountOutMinimum;
      s_swapAutomator.performUpkeep(data);

      assertGe(
        s_mockLink.balanceOf(i_receiver),
        recipientBalanceBefore + totalAmountOutMinimum,
        "Invariant violated: total amount out from swaps greater then threshold"
      );

      // Clear the fuzzed assets state and clear all balances on the FeeAggregator contract
      for (uint256 i; i < allowlistedAssets.length; ++i) {
        delete s_fuzzedAssets[allowlistedAssets[i]];
        deal(allowlistedAssets[i], address(s_feeAggregator), 0);
      }
    }
  }

  /// @notice Getter function to retrieve the total minimum expected amout out of all swaps
  /// @return The total minimum expected amount out of all swaps
  function getTotalAmountOutMinimum() public view returns (uint256) {
    return s_totalAmountOutMinimum;
  }

  /// @custom:see SwapAutomator._convertToLink();
  function _convertToLink(
    uint256 assetAmount,
    IERC20Metadata asset,
    AggregatorV3Interface usdFeed
  ) private view returns (uint256) {
    uint256 tokenDecimals = asset.decimals();
    if (tokenDecimals < 18) {
      return (assetAmount * _getAssetPrice(usdFeed) * 10 ** (18 - tokenDecimals)) / _getAssetPrice(s_mockLinkUsdFeed);
    } else {
      return (assetAmount * _getAssetPrice(usdFeed)) / _getAssetPrice(s_mockLinkUsdFeed) / 10 ** (tokenDecimals - 18);
    }
  }

  function test_upkeepHandlerTest() public {}
}
