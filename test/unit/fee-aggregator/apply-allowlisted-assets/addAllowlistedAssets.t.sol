// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

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
    s_assets.push(ASSET_1);
    s_assets.push(ASSET_2);
    _changePrank(ASSET_ADMIN);
  }

  function test_applyAllowlistedAssetUpdates_RevertWhen_CallerDoesNotHaveASSET_ADMIN_ROLE()
    public
    whenCallerIsNotAssetManager
  {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.ASSET_ADMIN_ROLE)
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
    assets[0] = ASSET_1;
    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.AssetAddedToAllowlist(ASSET_1);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), assets);

    address[] memory allowlistedAssets = s_feeAggregatorSender.getAllowlistedAssets();
    (bool areAssetsAllowlisted, address asset) = s_feeAggregatorSender.areAssetsAllowlisted(assets);

    assertTrue(areAssetsAllowlisted);
    assertEq(asset, address(0));
    assertTrue(allowlistedAssets.length == 1);
    assertTrue(allowlistedAssets[0] == ASSET_1);
  }

  function test_applyAllowlistedAssetUpdates_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.AssetAddedToAllowlist(ASSET_1);
    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.AssetAddedToAllowlist(ASSET_2);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), s_assets);

    address[] memory allowlistedAssets = s_feeAggregatorSender.getAllowlistedAssets();
    (bool areAssetsAllowlisted, address asset) = s_feeAggregatorSender.areAssetsAllowlisted(allowlistedAssets);

    assertTrue(areAssetsAllowlisted);
    assertEq(asset, address(0));
    assertTrue(allowlistedAssets.length == 2);
    assertTrue(allowlistedAssets[0] == ASSET_1);
    assertTrue(allowlistedAssets[1] == ASSET_2);
  }
}
