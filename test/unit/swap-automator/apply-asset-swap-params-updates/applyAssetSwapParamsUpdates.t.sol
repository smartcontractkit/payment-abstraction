// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ApplyAssetSwapParamsUpdatesUnitTest is BaseUnitTest {
  address[] private s_swapAssets;
  SwapAutomator.AssetSwapParamsArgs[] private s_assetSwapParamsArgs;

  function setUp() public {
    s_swapAssets.push(i_asset1);
    s_assetSwapParamsArgs.push(
      SwapAutomator.AssetSwapParamsArgs({
        asset: i_asset1,
        swapParams: SwapAutomator.SwapParams({
          usdFeed: AggregatorV3Interface(i_asset1UsdFeed),
          maxSlippage: MAX_SLIPPAGE,
          minSwapSizeUsd: MIN_SWAP_SIZE,
          maxSwapSizeUsd: MAX_SWAP_SIZE,
          maxPriceDeviation: MAX_PRICE_DEVIATION,
          swapInterval: SWAP_INTERVAL,
          stalenessThreshold: STALENESS_THRESHOLD,
          path: ASSET_1_SWAP_PATH
        })
      })
    );
    s_swapAssets.push(i_asset2);
    s_assetSwapParamsArgs.push(
      SwapAutomator.AssetSwapParamsArgs({
        asset: i_asset2,
        swapParams: SwapAutomator.SwapParams({
          usdFeed: AggregatorV3Interface(i_asset2UsdFeed),
          maxSlippage: MAX_SLIPPAGE,
          minSwapSizeUsd: MIN_SWAP_SIZE,
          maxSwapSizeUsd: MAX_SWAP_SIZE,
          maxPriceDeviation: MAX_PRICE_DEVIATION,
          swapInterval: SWAP_INTERVAL,
          stalenessThreshold: STALENESS_THRESHOLD,
          path: ASSET_2_SWAP_PATH
        })
      })
    );

    _changePrank(i_assetAdmin);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), s_swapAssets);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_CallerDoesNotHaveASSET_ADMIN_ROLE()
    public
    whenCallerIsNotAssetManager
  {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.ASSET_ADMIN_ROLE)
    );
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_AssetListIsNotAllowlistedOnTheReceiver() public {
    s_assetSwapParamsArgs.pop();
    s_assetSwapParamsArgs[0].asset = i_invalidAsset;
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, i_invalidAsset));
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_FeedIsZeroAddress() public {
    s_assetSwapParamsArgs[0].swapParams.usdFeed = AggregatorV3Interface(address(0));
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_StalenessThresholdEqZero() public {
    s_assetSwapParamsArgs[0].swapParams.stalenessThreshold = 0;
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applySetSwapParamsUpdates_RevertWhen_SwapPathIsEmpty() public {
    s_assetSwapParamsArgs[0].swapParams.path = EMPTY_SWAP_PATH;
    vm.expectRevert(SwapAutomator.EmptySwapPath.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxSlippageIsZero() public {
    s_assetSwapParamsArgs[0].swapParams.maxSlippage = 0;
    vm.expectRevert(abi.encodeWithSelector(SwapAutomator.InvalidSlippage.selector, 0));
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxSlippageIsOneHundredPercent() public {
    uint16 maxSlippage = uint16(PercentageMath.PERCENTAGE_FACTOR);
    s_assetSwapParamsArgs[0].swapParams.maxSlippage = maxSlippage;
    vm.expectRevert(abi.encodeWithSelector(SwapAutomator.InvalidSlippage.selector, maxSlippage));
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxSlippageGreaterThanOneHundredPercent() public {
    uint16 maxSlippage = uint16(1 + PercentageMath.PERCENTAGE_FACTOR);
    s_assetSwapParamsArgs[0].swapParams.maxSlippage = maxSlippage;
    vm.expectRevert(abi.encodeWithSelector(SwapAutomator.InvalidSlippage.selector, maxSlippage));
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxPriceDeviationIsBelowMaxSlippage() public {
    s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation = 100;
    s_assetSwapParamsArgs[0].swapParams.maxSlippage = 101;
    vm.expectRevert(
      abi.encodeWithSelector(
        SwapAutomator.InvalidMaxPriceDeviation.selector, s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation
      )
    );
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxPriceDeviationIsOneHundredPercent() public {
    uint16 maxPriceDeviation = uint16(PercentageMath.PERCENTAGE_FACTOR);
    s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation = maxPriceDeviation;
    vm.expectRevert(abi.encodeWithSelector(SwapAutomator.InvalidMaxPriceDeviation.selector, maxPriceDeviation));
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxPriceDeviationGreaterThanOneHundredPercent() public {
    s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation = uint16(1 + PercentageMath.PERCENTAGE_FACTOR);
    vm.expectRevert(
      abi.encodeWithSelector(
        SwapAutomator.InvalidMaxPriceDeviation.selector, s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation
      )
    );
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MinSwapSizeEqZero() public {
    s_assetSwapParamsArgs[0].swapParams.minSwapSizeUsd = 0;
    vm.expectRevert(SwapAutomator.InvalidMinSwapSizeUsd.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MinSwapSizeGtMaxSwapSize() public {
    s_assetSwapParamsArgs[0].swapParams.minSwapSizeUsd = s_assetSwapParamsArgs[0].swapParams.maxSwapSizeUsd + 1;
    vm.expectRevert(SwapAutomator.InvalidMinSwapSizeUsd.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
  }

  function test_applyAssetSwapParamsUpdates_RemoveAsset() public {
    s_assetSwapParamsArgs.pop();
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);
    assertFalse(s_swapAutomator.getHashedSwapPath(i_asset1) == bytes32(0));

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = i_asset1;

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsRemoved(i_asset1);

    s_swapAutomator.applyAssetSwapParamsUpdates(assetsToRemove, new SwapAutomator.AssetSwapParamsArgs[](0));
    assertTrue(s_swapAutomator.getHashedSwapPath(i_asset1) == bytes32(0));
  }

  function test_applyAssetSwapParamsUpdates_SingleAssetWithSamePriceDeviation() public {
    s_assetSwapParamsArgs.pop();
    s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation = s_assetSwapParamsArgs[0].swapParams.maxSlippage;

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(i_asset1, s_assetSwapParamsArgs[0].swapParams);

    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(i_asset1);

    _assertSwapParamsEquality(swapParams, s_assetSwapParamsArgs[0].swapParams);
  }

  function test_applyAssetSwapParamsUpdates_SingleAssetWithHigherMaxPriceDeviation() public {
    s_assetSwapParamsArgs.pop();
    s_assetSwapParamsArgs[0].swapParams.maxPriceDeviation = s_assetSwapParamsArgs[0].swapParams.maxSlippage + 1;

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(i_asset1, s_assetSwapParamsArgs[0].swapParams);

    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(i_asset1);

    _assertSwapParamsEquality(swapParams, s_assetSwapParamsArgs[0].swapParams);
  }

  function test_applyAssetSwapParamsUpdates_AssetAlreadyAllowlisted() public {
    s_assetSwapParamsArgs.pop();

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(i_asset1, s_assetSwapParamsArgs[0].swapParams);

    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);

    s_assetSwapParamsArgs[0].swapParams.usdFeed = AggregatorV3Interface(i_asset2UsdFeed);

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(i_asset1, s_assetSwapParamsArgs[0].swapParams);

    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(i_asset1);

    _assertSwapParamsEquality(swapParams, s_assetSwapParamsArgs[0].swapParams);
  }

  function test_applyAssetSwapParamsUpdates_MultipleAssets() public {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(i_asset1, s_assetSwapParamsArgs[0].swapParams);
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(i_asset2, s_assetSwapParamsArgs[1].swapParams);

    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), s_assetSwapParamsArgs);

    SwapAutomator.SwapParams memory asset1SwapParams = s_swapAutomator.getAssetSwapParams(i_asset1);
    SwapAutomator.SwapParams memory asset2SwapParams = s_swapAutomator.getAssetSwapParams(i_asset2);

    _assertSwapParamsEquality(asset1SwapParams, s_assetSwapParamsArgs[0].swapParams);
    _assertSwapParamsEquality(asset2SwapParams, s_assetSwapParamsArgs[1].swapParams);
  }

  function _assertSwapParamsEquality(
    SwapAutomator.SwapParams memory swapParams1,
    SwapAutomator.SwapParams memory swapParams2
  ) internal {
    assertEq(address(swapParams1.usdFeed), address(swapParams2.usdFeed));
    assertEq(swapParams1.maxSlippage, swapParams2.maxSlippage);
    assertEq(swapParams1.minSwapSizeUsd, swapParams2.minSwapSizeUsd);
    assertEq(swapParams1.maxSwapSizeUsd, swapParams2.maxSwapSizeUsd);
    assertEq(swapParams1.maxPriceDeviation, swapParams2.maxPriceDeviation);
    assertEq(swapParams1.swapInterval, swapParams2.swapInterval);
    assertEq(swapParams1.path, swapParams2.path);
  }
}
