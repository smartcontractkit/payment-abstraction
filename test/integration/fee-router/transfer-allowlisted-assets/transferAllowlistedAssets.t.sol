// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract FeeRouter_TransferAllowlistedAssetsIntegrationTest is BaseIntegrationTest {
  address[] private s_assets;
  uint256[] private s_amounts;

  modifier whenCallerIsNotBridger() {
    _changePrank(OWNER);
    _;
  }

  function setUp() public {
    s_assets.push(address(s_mockWETH));
    s_assets.push(address(s_mockLINK));
    s_amounts.push(1 ether);
    s_amounts.push(1 ether);

    deal(address(s_mockLINK), address(s_feeRouter), 1 ether);
    deal(address(s_mockWETH), address(s_feeRouter), 1 ether);

    _changePrank(ASSET_ADMIN);
    address[] memory allowlistedAssets = new address[](2);
    allowlistedAssets[0] = address(s_mockWETH);
    allowlistedAssets[1] = address(s_mockLINK);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), allowlistedAssets);

    _changePrank(BRIDGER);
  }

  function test_transferAllowlistedAssets_MultipleTokens() public {
    vm.expectEmit(address(s_feeRouter));
    emit FeeRouter.AssetTransferred(address(s_feeAggregatorReceiver), address(s_mockWETH), 1 ether);
    vm.expectEmit(address(s_feeRouter));
    emit FeeRouter.AssetTransferred(address(s_feeAggregatorReceiver), address(s_mockLINK), 1 ether);

    s_feeRouter.transferAllowlistedAssets(s_assets, s_amounts);

    assertEq(s_mockWETH.balanceOf(address(s_feeAggregatorReceiver)), 1 ether);
    assertEq(s_mockWETH.balanceOf(address(s_feeRouter)), 0);
    assertEq(s_mockLINK.balanceOf(address(s_feeAggregatorReceiver)), 1 ether);
    assertEq(s_mockLINK.balanceOf(address(s_feeRouter)), 0);
  }

  function test_transferAllowlistedAssets_RevertWhen_CallerDoesNotHaveBRIDGER_ROLE() public whenCallerIsNotBridger {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.BRIDGER_ROLE)
    );
    s_feeRouter.transferAllowlistedAssets(s_assets, s_amounts);
  }

  function test_transferAllowlistedAssets_RevertWhen_EmptyAssetList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_feeRouter.transferAllowlistedAssets(new address[](0), new uint256[](0));
  }

  function test_transferAllowlistedAssets_RevertWhen_AssetListLengthNeqAmountListLength() public {
    s_assets.pop();
    vm.expectRevert(Errors.ArrayLengthMismatch.selector);
    s_feeRouter.transferAllowlistedAssets(s_assets, s_amounts);
  }

  function test_transferAllowlistedAssets_RevertWhen_InvalidZeroAmount() public {
    s_amounts[0] = 0;
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeRouter.transferAllowlistedAssets(s_assets, s_amounts);
  }

  function test_transferAllowlistedAssets_RevertWhen_AssetNotAllowlisted() public {
    _changePrank(ASSET_ADMIN);
    address[] memory allowlistedAssets = new address[](1);
    allowlistedAssets[0] = address(s_mockWETH);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(allowlistedAssets, new address[](0));

    _changePrank(BRIDGER);
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, address(s_mockWETH)));
    s_feeRouter.transferAllowlistedAssets(s_assets, s_amounts);
  }
}
