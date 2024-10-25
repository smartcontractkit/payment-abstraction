// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetFeeAggregatorUnitTest is BaseUnitTest {
  address private constant NEW_FEE_AGGREGATOR_RECEIVER = address(999);

  function test_setFeeAggregatorReceiver_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_swapAutomator.setFeeAggregator(NEW_FEE_AGGREGATOR_RECEIVER);
  }

  function test_setFeeAggregatorReceiver_RevertWhen_FeeAggregatorReceiverAddressZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_swapAutomator.setFeeAggregator(address(0));
  }

  function test_setFeeAggregatorReceiver_RevertWhen_FeeAggregatorReceiverAddressNotUpdated() public {
    vm.expectRevert(Errors.FeeAggregatorNotUpdated.selector);
    s_swapAutomator.setFeeAggregator(address(s_feeAggregatorReceiver));
  }

  function test_setFeeAggregatorReceiver_UpdatesFeeAggregatorReceiver() external {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.FeeAggregatorSet(NEW_FEE_AGGREGATOR_RECEIVER);
    s_swapAutomator.setFeeAggregator(NEW_FEE_AGGREGATOR_RECEIVER);
    assertEq(address(s_swapAutomator.getFeeAggregator()), NEW_FEE_AGGREGATOR_RECEIVER);
  }
}
