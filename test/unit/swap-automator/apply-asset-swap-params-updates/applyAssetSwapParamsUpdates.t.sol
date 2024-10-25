// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
  SwapAutomator.SwapParams[] private s_swapParams;

  function setUp() public {
    s_swapAssets.push(ASSET_1);
    s_swapParams.push(
      SwapAutomator.SwapParams({
        oracle: AggregatorV3Interface(ASSET_1_ORACLE),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        path: ASSET_1_SWAP_PATH
      })
    );
    s_swapAssets.push(ASSET_2);
    s_swapParams.push(
      SwapAutomator.SwapParams({
        oracle: AggregatorV3Interface(ASSET_2_ORACLE),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        path: ASSET_2_SWAP_PATH
      })
    );

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorReceiver.applyAllowlistedAssets(new address[](0), s_swapAssets);
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_CallerDoesNotHaveASSET_ADMIN_ROLE()
    public
    whenCallerIsNotAssetManager
  {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.ASSET_ADMIN_ROLE)
    );
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_AssetListLengthDoesNotMatchSwapParamsLength() public {
    address[] memory assetList = new address[](1);
    assetList[0] = ASSET_1;
    vm.expectRevert(Errors.AssetsSwapParamsMismatch.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: assetList, assetsSwapParams: s_swapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_AssetListIsNotAllowlistedOnTheReceiver() public {
    address[] memory assetList = new address[](1);
    assetList[0] = INVALID_ASSET;
    SwapAutomator.SwapParams[] memory newSwapParams = new SwapAutomator.SwapParams[](1);
    newSwapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ASSET_1_ORACLE),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: ASSET_1_SWAP_PATH
    });
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, INVALID_ASSET));
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: assetList, assetsSwapParams: newSwapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_OracleIsZeroAddress() public {
    s_swapParams[0].oracle = AggregatorV3Interface(address(0));
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );
  }

  function test_applySetSwapParamsUpdates_RevertWhen_SwapPathIsEmpty() public {
    s_swapParams[0].path = EMPTY_SWAP_PATH;
    vm.expectRevert(Errors.EmptySwapPath.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxSlippageIsZero() public {
    s_swapParams[0].maxSlippage = 0;
    vm.expectRevert(Errors.InvalidSlippage.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxSlippageIsOneHundredPercent() public {
    s_swapParams[0].maxSlippage = uint16(PercentageMath.PERCENTAGE_FACTOR);
    vm.expectRevert(Errors.InvalidSlippage.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RevertWhen_MaxSlippageGreaterThanOneHundredPercent() public {
    s_swapParams[0].maxSlippage = uint16(1 + PercentageMath.PERCENTAGE_FACTOR);
    vm.expectRevert(Errors.InvalidSlippage.selector);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );
  }

  function test_applyAssetSwapParamsUpdates_RemoveAsset() public {
    address[] memory newSwapAssets = new address[](1);
    SwapAutomator.SwapParams[] memory newSwapParams = new SwapAutomator.SwapParams[](1);
    newSwapAssets[0] = ASSET_1;
    newSwapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ASSET_1_ORACLE),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: ASSET_1_SWAP_PATH
    });
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: newSwapAssets, assetsSwapParams: newSwapParams})
    );
    assertFalse(s_swapAutomator.getHashedSwapPath(ASSET_1) == bytes32(0));

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = ASSET_1;

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsRemoved(ASSET_1);

    s_swapAutomator.applyAssetSwapParamsUpdates(
      assetsToRemove,
      SwapAutomator.AssetSwapParamsArgs({assets: new address[](0), assetsSwapParams: new SwapAutomator.SwapParams[](0)})
    );
    assertTrue(s_swapAutomator.getHashedSwapPath(ASSET_1) == bytes32(0));
  }

  function test_applyAssetSwapParamsUpdates_SingleAsset() public {
    address[] memory newSwapAssets = new address[](1);
    SwapAutomator.SwapParams[] memory newSwapParams = new SwapAutomator.SwapParams[](1);
    newSwapAssets[0] = ASSET_1;
    newSwapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ASSET_1_ORACLE),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: ASSET_1_SWAP_PATH
    });

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(ASSET_1, newSwapParams[0]);

    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: newSwapAssets, assetsSwapParams: newSwapParams})
    );

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(ASSET_1);

    _assertSwapParamsEquality(swapParams, newSwapParams[0]);
  }

  function test_applyAssetSwapParamsUpdates_AssetAlreadyAllowlisted() public {
    SwapAutomator.SwapParams[] memory newSwapParams = new SwapAutomator.SwapParams[](1);
    address[] memory swapAssets = new address[](1);
    swapAssets[0] = ASSET_1;
    newSwapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ASSET_1_ORACLE),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: ASSET_1_SWAP_PATH
    });

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(ASSET_1, newSwapParams[0]);

    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: swapAssets, assetsSwapParams: newSwapParams})
    );

    newSwapParams[0].oracle = AggregatorV3Interface(ASSET_2_ORACLE);

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(ASSET_1, newSwapParams[0]);

    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: swapAssets, assetsSwapParams: newSwapParams})
    );

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(ASSET_1);

    _assertSwapParamsEquality(swapParams, newSwapParams[0]);
  }

  function test_applyAssetSwapParamsUpdates_MultipleAssets() public {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(ASSET_1, s_swapParams[0]);
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapParamsUpdated(ASSET_2, s_swapParams[1]);

    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: s_swapAssets, assetsSwapParams: s_swapParams})
    );

    SwapAutomator.SwapParams memory asset1SwapParams = s_swapAutomator.getAssetSwapParams(ASSET_1);
    SwapAutomator.SwapParams memory asset2SwapParams = s_swapAutomator.getAssetSwapParams(ASSET_2);

    _assertSwapParamsEquality(asset1SwapParams, s_swapParams[0]);
    _assertSwapParamsEquality(asset2SwapParams, s_swapParams[1]);
  }

  function _assertSwapParamsEquality(
    SwapAutomator.SwapParams memory swapParams1,
    SwapAutomator.SwapParams memory swapParams2
  ) internal {
    assertEq(address(swapParams1.oracle), address(swapParams2.oracle));
    assertEq(swapParams1.maxSlippage, swapParams2.maxSlippage);
    assertEq(swapParams1.minSwapSizeUsd, swapParams2.minSwapSizeUsd);
    assertEq(swapParams1.maxSwapSizeUsd, swapParams2.maxSwapSizeUsd);
    assertEq(swapParams1.maxPriceDeviation, swapParams2.maxPriceDeviation);
    assertEq(swapParams1.swapInterval, swapParams2.swapInterval);
    assertEq(swapParams1.path, swapParams2.path);
  }
}
