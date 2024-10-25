// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

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
    s_assets.push(ASSET_1);
    s_assets.push(ASSET_2);

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorReceiver.applyAllowlistedAssets(new address[](0), s_assets);
  }

  function test_removeAllowlistedAssets_RevertWhen_AssetIsNotAlreadyAllowlisted() public {
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = INVALID_ASSET;
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, INVALID_ASSET));
    s_feeAggregatorReceiver.applyAllowlistedAssets(assetsToRemove, new address[](0));
  }

  function test_removeAllowlistedAssets_SingleAsset() external {
    address[] memory assets = new address[](1);
    assets[0] = ASSET_1;
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetRemovedFromAllowlist(ASSET_1);
    s_feeAggregatorReceiver.applyAllowlistedAssets(assets, new address[](0));

    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();
    (bool areAssetsAllowlisted, address asset) = s_feeAggregatorSender.areAssetsAllowlisted(assets);

    assertEq(allowlistedAssets.length, 1);
    assertEq(allowlistedAssets[0], ASSET_2);
    assertFalse(areAssetsAllowlisted);
    assertEq(asset, ASSET_1);
  }

  function test_removeAllowlistedAssets_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetRemovedFromAllowlist(ASSET_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetRemovedFromAllowlist(ASSET_2);
    s_feeAggregatorReceiver.applyAllowlistedAssets(s_assets, new address[](0));

    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();
    (bool areAssetsAllowlisted, address asset) = s_feeAggregatorSender.areAssetsAllowlisted(s_assets);

    assertEq(allowlistedAssets.length, 0);
    assertFalse(areAssetsAllowlisted);
    assertEq(asset, ASSET_1);
  }
}
