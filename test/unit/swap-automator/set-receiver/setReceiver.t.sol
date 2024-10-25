// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {FeeAggregator} from "src/FeeAggregator.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetLINKReceiverUnitTests is BaseUnitTest {
  function test_SetLINKReceiver_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_swapAutomator.setLinkReceiver(RECEIVER);
  }

  function test_SetLINKReceiver_RevertWhen_SwapAutomatorAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_swapAutomator.setLinkReceiver(address(0));
  }

  function test_SetLINKReceiver_RevertWhen_NotUpdated() public {
    vm.expectRevert(Errors.LINKReceiverNotUpdated.selector);
    s_swapAutomator.setLinkReceiver(RECEIVER);
  }

  function test_SetLINKReceiver() public {
    address newReceiver = address(vm.addr(1));
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.LinkReceiverSet(newReceiver);
    s_swapAutomator.setLinkReceiver(newReceiver);
    assertEq(address(s_swapAutomator.getLinkReceiver()), newReceiver);
  }
}
