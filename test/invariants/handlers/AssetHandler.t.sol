// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {FeeAggregator} from "src/FeeAggregator.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Constants} from "test/Constants.t.sol";

import {Test} from "forge-std/Test.sol";

/// @title This contract is used to fuzz assets swap parameters
/// Function exposed to the fuzzer:
/// - applyAssetSwapParamsUpdates
contract AssetHandler is Constants, Test {
  uint128 private constant MIN_SWAP_SIZE_LOWER_BOUND = 1_000e8;
  uint128 private constant MIN_SWAP_SIZE_UPPER_BOUND = 10_000e8;
  uint128 private constant MAX_SWAP_SIZE_UPPER_BOUND = 100_000e8;

  FeeAggregator private s_feeAggregatorReceiver;
  SwapAutomator private s_swapAutomator;

  constructor(FeeAggregator feeAggregatorReceiver, SwapAutomator swapAutomator) {
    s_feeAggregatorReceiver = feeAggregatorReceiver;
    s_swapAutomator = swapAutomator;
  }

  /// @notice Simulates an asset's swap parameters
  /// @param index The index of the asset in the allowlisted assets array - bound between 0 and the
  /// length of the array
  /// @param maxSlippage The maximum allowed slippage for the swap in basis points - bound between 1
  /// and 200
  /// @param minSwapSize The minimum swap size expressed in USD 8 decimals - bound between 1_000e8
  /// and 10_000e8
  /// @param maxSwapSize The maximum swap size expressed in USD 8 decimals - bound between 10_000e8
  /// and 100_000e8
  /// @param maxPriceDeviation The maximum price deviation from swapped out amount vs price feed
  /// estiamtes - bound between 1
  /// and 200
  function setAssetSwapParams(
    uint8 index,
    uint16 maxSlippage,
    uint128 minSwapSize,
    uint128 maxSwapSize,
    uint16 maxPriceDeviation
  ) public {
    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();
    index = uint8(bound(index, 0, allowlistedAssets.length - 1));
    maxSlippage = uint16(bound(maxSlippage, 1, MAX_SLIPPAGE)); // 0.01% to 2%
    maxPriceDeviation = uint16(bound(maxPriceDeviation, 1, MAX_PRICE_DEVIATION));
    minSwapSize = uint128(bound(minSwapSize, MIN_SWAP_SIZE_LOWER_BOUND, MIN_SWAP_SIZE_UPPER_BOUND));
    maxSwapSize = uint128(bound(maxSwapSize, MIN_SWAP_SIZE_UPPER_BOUND, MAX_SWAP_SIZE_UPPER_BOUND));

    SwapAutomator.SwapParams memory currentSwapParams = s_swapAutomator.getAssetSwapParams(allowlistedAssets[index]);
    SwapAutomator.SwapParams[] memory swapParams = new SwapAutomator.SwapParams[](1);
    address[] memory swapAssets = new address[](1);
    swapAssets[0] = allowlistedAssets[index];
    swapParams[0] = SwapAutomator.SwapParams({
      oracle: currentSwapParams.oracle,
      maxSlippage: maxSlippage,
      minSwapSizeUsd: minSwapSize,
      maxSwapSizeUsd: maxSwapSize,
      maxPriceDeviation: maxPriceDeviation,
      swapInterval: currentSwapParams.swapInterval,
      path: currentSwapParams.path
    });

    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: swapAssets, assetsSwapParams: swapParams})
    );
  }

  function test_assetHandlerTest() public {}
}
