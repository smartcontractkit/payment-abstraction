// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RemoveAllowlistAssetsUnitTest is BaseUnitTest {
  address[] private s_assets;

  function setUp() public {
    s_assets.push(i_asset1);
    s_assets.push(i_asset2);

    _changePrank(i_assetAdmin);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), s_assets);
  }

  function test_removeAllowlistedAssets_RevertWhen_AssetIsNotAlreadyAllowlisted() public {
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = i_invalidAsset;
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, i_invalidAsset));
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(assetsToRemove, new address[](0));
  }

  function test_removeAllowlistedAssets_SingleAsset() external {
    address[] memory assets = new address[](1);
    assets[0] = i_asset1;
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetRemovedFromAllowlist(i_asset1);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(assets, new address[](0));

    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();

    assertEq(allowlistedAssets.length, 1);
    assertEq(allowlistedAssets[0], i_asset2);
    assertFalse(s_feeAggregatorSender.isAssetAllowlisted(i_asset1));
  }

  function test_removeAllowlistedAssets_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetRemovedFromAllowlist(i_asset1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetRemovedFromAllowlist(i_asset2);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(s_assets, new address[](0));

    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();

    assertEq(allowlistedAssets.length, 0);
    assertFalse(s_feeAggregatorSender.isAssetAllowlisted(i_asset1));
    assertFalse(s_feeAggregatorSender.isAssetAllowlisted(i_asset2));
  }
}
