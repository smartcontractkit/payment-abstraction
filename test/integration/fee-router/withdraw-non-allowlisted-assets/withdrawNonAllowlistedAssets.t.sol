// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract FeeRouter_WithdrawNonAllowlistedAssetsIntegrationTest is BaseIntegrationTest {
  address[] private s_assets;
  uint256[] private s_amounts;

  function setUp() public {
    deal(address(s_mockWETH), address(s_feeRouter), 1 ether);
    deal(address(s_mockUSDC), address(s_feeRouter), 1000e6);
    deal(address(s_mockWBTC), address(s_feeRouter), 1e8);

    address[] memory allowlistedAssets = new address[](1);
    allowlistedAssets[0] = address(s_mockWETH);

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorReceiver.applyAllowlistedAssets(new address[](0), allowlistedAssets);

    _changePrank(WITHDRAWER);
    s_assets.push(address(s_mockWBTC));
    s_assets.push(address(s_mockUSDC));
    s_amounts.push(1e8);
    s_amounts.push(1000e6);

    vm.label(address(s_mockUSDC), "Mock USDC");
    vm.label(address(s_mockWBTC), "Mock WBTC");
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_CallerDoesNotHaveWITHDRAWER_ROLE()
    public
    whenCallerIsNotWithdrawer
  {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.WITHDRAWER_ROLE)
    );
    s_feeRouter.withdrawNonAllowlistedAssets(s_assets, s_amounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_EmptyAssetList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_feeRouter.withdrawNonAllowlistedAssets(new address[](0), new uint256[](0));
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_AssetIsAddressZero() public {
    s_assets[0] = address(0);
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeRouter.withdrawNonAllowlistedAssets(s_assets, s_amounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_AmountIsZero() public {
    s_amounts[0] = 0;
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeRouter.withdrawNonAllowlistedAssets(s_assets, s_amounts);
  }

  function test_withdrawNonAllowlistedAssets_RevertWhen_AssetIsAllowlisted() public {
    address[] memory assets = new address[](1);
    assets[0] = address(s_mockWETH);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1 ether;

    vm.expectRevert(abi.encodeWithSelector(Errors.AssetAllowlisted.selector, address(s_mockWETH)));
    s_feeRouter.withdrawNonAllowlistedAssets(assets, amounts);
  }

  function test_withdrawNonAllowlistedAssets_SingleAsset() public {
    s_assets.pop();
    s_amounts.pop();

    vm.expectEmit(address(s_feeRouter));
    emit EmergencyWithdrawer.AssetTransferred(WITHDRAWER, s_assets[0], s_amounts[0]);

    s_feeRouter.withdrawNonAllowlistedAssets(s_assets, s_amounts);

    assertEq(s_mockWBTC.balanceOf(WITHDRAWER), s_amounts[0]);
    assertEq(s_mockWBTC.balanceOf(address(s_feeRouter)), 0);
  }

  function test_withdrawNonAllowlistedAssets_MultipleAssets() public {
    vm.expectEmit(address(s_feeRouter));
    emit EmergencyWithdrawer.AssetTransferred(WITHDRAWER, s_assets[0], s_amounts[0]);
    vm.expectEmit(address(s_feeRouter));
    emit EmergencyWithdrawer.AssetTransferred(WITHDRAWER, s_assets[1], s_amounts[1]);

    s_feeRouter.withdrawNonAllowlistedAssets(s_assets, s_amounts);

    assertEq(s_mockWBTC.balanceOf(WITHDRAWER), s_amounts[0]);
    assertEq(s_mockUSDC.balanceOf(WITHDRAWER), s_amounts[1]);
    assertEq(s_mockWBTC.balanceOf(address(s_feeRouter)), 0);
    assertEq(s_mockUSDC.balanceOf(address(s_feeRouter)), 0);
  }
}
