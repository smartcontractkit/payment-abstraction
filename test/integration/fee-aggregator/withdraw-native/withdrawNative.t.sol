// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract FeeAggregator_withdrawNativeIntegrationTest is BaseIntegrationTest {
  function setUp() public {
    deal(address(s_feeAggregatorReceiver), 1 ether);

    _changePrank(WITHDRAWER);
  }

  function test_withdrawNative() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.NonAllowlistedAssetWithdrawn(WITHDRAWER, address(0), 1 ether);

    s_feeAggregatorReceiver.withdrawNative(payable(WITHDRAWER), 1 ether);

    assertEq(address(s_feeAggregatorReceiver).balance, 0);
    assertEq(WITHDRAWER.balance, 1 ether);
  }

  function test_withdrawNative_RevertWhen_CallerDoesNotHaveWITHDRAWER_ROLE() public whenCallerIsNotWithdrawer {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.WITHDRAWER_ROLE)
    );
    s_feeAggregatorReceiver.withdrawNative(payable(OWNER), 1 ether);
  }

  function test_withdrawNative_RevertWhen_AssetIsAllowlisted() public givenAssetIsAllowlisted(address(s_mockWETH)) {
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetAllowlisted.selector, address(s_mockWETH)));
    s_feeAggregatorReceiver.withdrawNative(payable(WITHDRAWER), 1 ether);
  }

  function test_withdrawNative_RevertWhen_ToEqAddressZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeAggregatorReceiver.withdrawNative(payable(address(0)), 1 ether);
  }

  function test_withdrawNative_RevertWhen_AmountIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeAggregatorReceiver.withdrawNative(payable(WITHDRAWER), 0);
  }
}
