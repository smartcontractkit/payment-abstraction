// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {FeeAggregator} from "src/FeeAggregator.sol";
import {Common} from "src/libraries/Common.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract FeeAggregator_WithdrawNonAllowlistedAssetsIntegrationTest is BaseIntegrationTest {
  Common.AssetAmount[] private s_assetAmounts;

  function setUp() public {
    deal(address(s_mockWETH), address(s_feeAggregatorReceiver), 1 ether);
    deal(address(s_mockUSDC), address(s_feeAggregatorReceiver), 1000e6);
    deal(address(s_mockWBTC), address(s_feeAggregatorReceiver), 1e8);

    address[] memory allowlistedAssets = new address[](1);
    allowlistedAssets[0] = address(s_mockWETH);

    _changePrank(i_assetAdmin);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), allowlistedAssets);

    _changePrank(i_withdrawer);
    s_assetAmounts.push(Common.AssetAmount({asset: address(s_mockWBTC), amount: 1e8}));
    s_assetAmounts.push(Common.AssetAmount({asset: address(s_mockUSDC), amount: 1000e6}));
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_ContractIsPaused()
    public
    givenContractIsPaused(address(s_feeAggregatorReceiver))
  {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_CallerDoesNotHaveWITHDRAWER_ROLE()
    public
    whenCallerIsNotWithdrawer
  {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.WITHDRAWER_ROLE)
    );
    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_EmptyAssetList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, new Common.AssetAmount[](0));
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_AssetIsAddressZero() public {
    s_assetAmounts[0].asset = address(0);
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_AmountIsZero() public {
    s_assetAmounts[0].amount = 0;
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_AssetIsAllowlisted() public {
    s_assetAmounts[0].asset = address(s_mockUSDC);
    s_assetAmounts[1].asset = address(s_mockWETH);
    s_assetAmounts[0].amount = 1000e6;
    s_assetAmounts[1].amount = 1 ether;

    vm.expectRevert(abi.encodeWithSelector(Errors.AssetAllowlisted.selector, address(s_mockWETH)));
    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);
  }

  function test_withdrawNonAllowlistedAssets_SingleAsset() public {
    s_assetAmounts.pop();

    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.NonAllowlistedAssetWithdrawn(i_withdrawer, s_assetAmounts[0].asset, s_assetAmounts[0].amount);

    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);

    assertEq(s_mockWBTC.balanceOf(i_withdrawer), s_assetAmounts[0].amount);
    assertEq(s_mockWBTC.balanceOf(address(s_feeAggregatorReceiver)), 0);
  }

  function test_withdrawNonAllowlistedAssets_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.NonAllowlistedAssetWithdrawn(i_withdrawer, s_assetAmounts[0].asset, s_assetAmounts[0].amount);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.NonAllowlistedAssetWithdrawn(i_withdrawer, s_assetAmounts[1].asset, s_assetAmounts[1].amount);

    s_feeAggregatorReceiver.withdrawNonAllowlistedAssets(i_withdrawer, s_assetAmounts);

    assertEq(s_mockWBTC.balanceOf(i_withdrawer), s_assetAmounts[0].amount);
    assertEq(s_mockUSDC.balanceOf(i_withdrawer), s_assetAmounts[1].amount);
    assertEq(s_mockWBTC.balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_mockUSDC.balanceOf(address(s_feeAggregatorReceiver)), 0);
  }
}
