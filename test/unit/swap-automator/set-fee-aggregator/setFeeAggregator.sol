// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapAutomator} from "src/SwapAutomator.sol";

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract SwapAutomator_SetFeeAggregatorUnitTest is BaseUnitTest {
  address private immutable i_newFeeAggregatorReciever = makeAddr("newFeeAggregatorReciever");

  function setUp() public {
    vm.mockCall(
      i_newFeeAggregatorReciever,
      abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IFeeAggregator).interfaceId),
      abi.encode(true)
    );
  }

  function test_setFeeAggregatorReceiver_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_nonOwner, DEFAULT_ADMIN_ROLE)
    );
    s_swapAutomator.setFeeAggregator(i_newFeeAggregatorReciever);
  }

  function test_setFeeAggregatorReceiver_RevertWhen_FeeAggregatorReceiverAddressZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_swapAutomator.setFeeAggregator(address(0));
  }

  function test_setFeeAggregatorReceiver_RevertWhen_FeeAggregatorReceiverAddressNotUpdated() public {
    vm.expectRevert(Errors.ValueNotUpdated.selector);
    s_swapAutomator.setFeeAggregator(address(s_feeAggregatorReceiver));
  }

  function test_setFeeAggregatorReceiver_RevertWhen_FeeAggregatorDoesNotSupportIFeeAggregatorInterface() public {
    vm.mockCall(
      i_newFeeAggregatorReciever,
      abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IFeeAggregator).interfaceId),
      abi.encode(false)
    );
    vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFeeAggregator.selector, i_newFeeAggregatorReciever));
    s_swapAutomator.setFeeAggregator(i_newFeeAggregatorReciever);
  }

  function test_setFeeAggregatorReceiver_UpdatesFeeAggregatorReceiver() external {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.FeeAggregatorSet(i_newFeeAggregatorReciever);
    s_swapAutomator.setFeeAggregator(i_newFeeAggregatorReciever);
    assertEq(address(s_swapAutomator.getFeeAggregator()), i_newFeeAggregatorReciever);
  }
}
