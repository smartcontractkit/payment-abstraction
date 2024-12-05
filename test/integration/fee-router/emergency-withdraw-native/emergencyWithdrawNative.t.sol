// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract FeeRouter_EmergencyWithdrawNativeIntegrationTest is BaseIntegrationTest {
  function setUp() public {
    deal(address(s_feeRouter), 1 ether);

    _changePrank(PAUSER);
    s_feeRouter.emergencyPause();
    _changePrank(OWNER);
  }

  function test_emergencyWithdrawNative() public {
    vm.expectEmit(address(s_feeRouter));
    emit EmergencyWithdrawer.AssetEmergencyWithdrawn(OWNER, address(0), 1 ether);

    s_feeRouter.emergencyWithdrawNative(payable(OWNER), 1 ether);

    assertEq(address(s_feeRouter).balance, 0);
    assertEq(OWNER.balance, 1 ether);
  }

  function test_emergencyWithdrawNative_RevertWhen_NotPaused() public givenContractIsNotPaused(address(s_feeRouter)) {
    vm.expectRevert(Pausable.ExpectedPause.selector);
    s_feeRouter.emergencyWithdrawNative(payable(OWNER), 1 ether);
  }

  function test_emergencyWithdrawNative_RevertWhen_CallerDoesNotHaveADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeRouter.emergencyWithdrawNative(payable(OWNER), 1 ether);
  }

  function test_emergencyWithdrawNative_RevertWhen_AmountIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeRouter.emergencyWithdrawNative(payable(OWNER), 0);
  }
}
