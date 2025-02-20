// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract AddAllowlistedAssetsUnitTest is BaseUnitTest {
  address[] private s_assets;

  function setUp() public {
    s_assets.push(i_asset1);
    s_assets.push(i_asset2);
    _changePrank(i_assetAdmin);
  }

  function test_applyAllowlistedAssetUpdates_RevertWhen_CallerDoesNotHaveASSET_ADMIN_ROLE()
    public
    whenCallerIsNotAssetManager
  {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.ASSET_ADMIN_ROLE)
    );
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);
  }

  function test_applyAllowlistedAssetUpdates_RevertWhen_ContractIsPaused()
    public
    givenContractIsPaused(address(s_feeAggregatorSender))
  {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);
  }

  function test_applyAllowlistedAssetUpdates_RevertWhen_AnyAssetIsZeroAddress() public {
    s_assets.push(address(0));
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);
  }

  function test_applyAllowlistedAssetUpdates_RevertWhen_AssetIsAlreadyAllowlisted() public {
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);

    vm.expectRevert(abi.encodeWithSelector(FeeAggregator.AssetAlreadyAllowlisted.selector, s_assets[0]));
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);
  }

  function test_applyAllowlistedAssetUpdates_SingleAsset() external {
    address[] memory assets = new address[](1);
    assets[0] = i_asset1;
    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.AssetAddedToAllowlist(i_asset1);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), assets);

    address[] memory allowlistedAssets = s_feeAggregatorSender.getAllowlistedAssets();

    assertTrue(s_feeAggregatorSender.isAssetAllowlisted(i_asset1));
    assertTrue(allowlistedAssets.length == 1);
    assertTrue(allowlistedAssets[0] == i_asset1);
  }

  function test_applyAllowlistedAssetUpdates_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.AssetAddedToAllowlist(i_asset1);
    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.AssetAddedToAllowlist(i_asset2);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);

    address[] memory allowlistedAssets = s_feeAggregatorSender.getAllowlistedAssets();

    assertTrue(s_feeAggregatorSender.isAssetAllowlisted(i_asset1));
    assertTrue(s_feeAggregatorSender.isAssetAllowlisted(i_asset2));
    assertTrue(allowlistedAssets.length == 2);
    assertTrue(allowlistedAssets[0] == i_asset1);
    assertTrue(allowlistedAssets[1] == i_asset2);
  }
}
