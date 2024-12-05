// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract FeeAggregator_EmergencyWithdrawNativeIntegrationTest is BaseIntegrationTest {
  function setUp() public {
    deal(address(s_feeAggregatorReceiver), 1 ether);

    _changePrank(PAUSER);
    s_feeAggregatorReceiver.emergencyPause();
    _changePrank(OWNER);
  }

  function test_emergencyWithdrawNative() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit EmergencyWithdrawer.AssetEmergencyWithdrawn(OWNER, address(0), 1 ether);

    s_feeAggregatorReceiver.emergencyWithdrawNative(payable(OWNER), 1 ether);

    assertEq(address(s_feeAggregatorReceiver).balance, 0);
    assertEq(OWNER.balance, 1 ether);
  }

  function test_emrgencyWithrawNative_RevertWhen_NotPaused()
    public
    givenContractIsNotPaused(address(s_feeAggregatorReceiver))
  {
    vm.expectRevert(Pausable.ExpectedPause.selector);
    s_feeAggregatorReceiver.emergencyWithdrawNative(payable(OWNER), 1 ether);
  }

  function test_emergencyWithdrawNative_RevertWhen_CallerDoesNotHaveADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeAggregatorReceiver.emergencyWithdrawNative(payable(OWNER), 1 ether);
  }

  function test_emergencyWithdrawNative_RevertWhen_AmountIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeAggregatorReceiver.emergencyWithdrawNative(payable(OWNER), 0);
  }

  function test_emergencyWithdrawNative_RevertWhen_FailedNativeTokenTransfer() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        EmergencyWithdrawer.FailedNativeTokenTransfer.selector,
        address(this),
        1 ether,
        abi.encodeWithSelector(bytes4(keccak256(bytes("Error(string)"))), "Receive not allowed")
      )
    );
    s_feeAggregatorReceiver.emergencyWithdrawNative(payable(address(this)), 1 ether);
  }

  receive() external payable {
    revert("Receive not allowed");
  }
}
