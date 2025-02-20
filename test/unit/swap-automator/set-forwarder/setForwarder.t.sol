// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SetForwarderUnitTest is BaseUnitTest {
  function test_setForwarder_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_nonOwner, DEFAULT_ADMIN_ROLE)
    );
    s_swapAutomator.setForwarder(i_forwarder);
  }

  function test_setForwarder_WhenContractIsPaused() public givenContractIsPaused(address(s_swapAutomator)) {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.ForwarderSet(i_forwarder);
    s_swapAutomator.setForwarder(i_forwarder);

    assertEq(i_forwarder, s_swapAutomator.getForwarder());
  }

  function test_setForwarder_RevertWhen_ForwarderAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_swapAutomator.setForwarder(address(0));
  }

  function test_setForwarder_RevertWhen_ForwarderAddressNotUpdated() public {
    _changePrank(i_owner);
    s_swapAutomator.setForwarder(i_forwarder);
    vm.expectRevert(Errors.ValueNotUpdated.selector);
    s_swapAutomator.setForwarder(i_forwarder);
  }

  function test_setForwarder() public {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.ForwarderSet(i_forwarder);
    s_swapAutomator.setForwarder(i_forwarder);

    assertEq(i_forwarder, s_swapAutomator.getForwarder());
  }
}
