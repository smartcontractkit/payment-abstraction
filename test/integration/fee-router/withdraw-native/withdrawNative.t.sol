// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FeeRouter} from "src/FeeRouter.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract FeeAggregator_withdrawNativeIntegrationTest is BaseIntegrationTest {
  function setUp() public {
    deal(address(s_feeRouter), 1 ether);

    _changePrank(i_withdrawer);
  }

  function test_withdrawNative() public {
    vm.expectEmit(address(s_feeRouter));
    emit FeeRouter.NonAllowlistedAssetWithdrawn(i_withdrawer, address(0), 1 ether);

    s_feeRouter.withdrawNative(payable(i_withdrawer), 1 ether);

    assertEq(address(s_feeRouter).balance, 0);
    assertEq(i_withdrawer.balance, 1 ether);
  }

  function test_withdrawNative_RevertWhen_ContractIsPaused() public givenContractIsPaused(address(s_feeRouter)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeRouter.withdrawNative(payable(i_withdrawer), 1 ether);
  }

  function test_withdrawNative_RevertWhen_CallerDoesNotHaveWITHDRAWER_ROLE() public whenCallerIsNotWithdrawer {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.WITHDRAWER_ROLE)
    );
    s_feeRouter.withdrawNative(payable(i_owner), 1 ether);
  }

  function test_withdrawNative_RevertWhen_AssetIsAllowlisted() public givenAssetIsAllowlisted(address(s_mockWETH)) {
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetAllowlisted.selector, address(s_mockWETH)));
    s_feeRouter.withdrawNative(payable(i_withdrawer), 1 ether);
  }

  function test_withdrawNative_RevertWhen_ToEqAddressZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeRouter.withdrawNative(payable(address(0)), 1 ether);
  }

  function test_withdrawNative_RevertWhen_AmountIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeRouter.withdrawNative(payable(i_withdrawer), 0);
  }
}
