// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract FeeAggregator_EmergencyWithdrawIntegrationTest is BaseIntegrationTest {
  address[] private s_assets;
  uint256[] private s_amounts;

  function setUp() public {
    deal(address(s_mockWETH), address(s_feeAggregatorReceiver), 1 ether);
    deal(address(s_mockUSDC), address(s_feeAggregatorReceiver), 1000e6);

    s_assets.push(address(s_mockWETH));
    s_assets.push(address(s_mockUSDC));
    s_amounts.push(1 ether);
    s_amounts.push(1000e6);

    _changePrank(PAUSER);
    s_feeAggregatorReceiver.emergencyPause();
    _changePrank(OWNER);
  }

  function test_emergencyWithdraw_RevertWhen_ContractIsNotPaused()
    public
    givenContractIsNotPaused(address(s_feeAggregatorReceiver))
  {
    vm.expectRevert(Pausable.ExpectedPause.selector);
    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_RevertWhen_EmptyAssetList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, new address[](0), new uint256[](0));
  }

  function test_emergencyWithdraw_RevertWhen_AssetIsAddressZero() public {
    s_assets[0] = address(0);
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_RevertWhen_AmountIsZero() public {
    s_amounts[0] = 0;
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_SingleAsset() public {
    s_assets.pop();
    s_amounts.pop();

    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit EmergencyWithdrawer.AssetEmergencyWithdrawn(OWNER, s_assets[0], s_amounts[0]);

    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, s_assets, s_amounts);

    assertEq(s_mockWETH.balanceOf(OWNER), s_amounts[0]);
    assertEq(s_mockWETH.balanceOf(address(s_feeAggregatorReceiver)), 0);
  }

  function test_emergencyWithdraw_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit EmergencyWithdrawer.AssetEmergencyWithdrawn(OWNER, s_assets[0], s_amounts[0]);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit EmergencyWithdrawer.AssetEmergencyWithdrawn(OWNER, s_assets[1], s_amounts[1]);

    s_feeAggregatorReceiver.emergencyWithdraw(OWNER, s_assets, s_amounts);

    assertEq(s_mockWETH.balanceOf(OWNER), s_amounts[0]);
    assertEq(s_mockUSDC.balanceOf(OWNER), s_amounts[1]);
    assertEq(s_mockWETH.balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_mockUSDC.balanceOf(address(s_feeAggregatorReceiver)), 0);
  }
}
