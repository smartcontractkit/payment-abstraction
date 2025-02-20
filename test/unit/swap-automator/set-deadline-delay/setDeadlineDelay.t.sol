// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapAutomator} from "src/SwapAutomator.sol";

import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SetDeadlineDelayUnitTest is BaseUnitTest {
  uint96 private constant NEW_DEADLINE_DELAY = DEADLINE_DELAY * 2;

  function setUp() public {
    _changePrank(i_assetAdmin);
  }

  function test_setDeadlineDelay_RevertWhen_CallerDoesNotHaveASSET_ADMIN_ROLE() public whenCallerIsNotAssetManager {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.ASSET_ADMIN_ROLE)
    );
    s_swapAutomator.setDeadlineDelay(NEW_DEADLINE_DELAY);
  }

  function test_setDeadlineDelay_RevertWhen_NewValueEqOldValue() public {
    vm.expectRevert(Errors.ValueNotUpdated.selector);
    s_swapAutomator.setDeadlineDelay(DEADLINE_DELAY);
  }

  function test_setDeadlineDelay_RevertWhen_NewValueLtMinThreshold() public {
    vm.expectRevert(
      abi.encodeWithSelector(SwapAutomator.DeadlineDelayTooLow.selector, DEADLINE_DELAY - 1, DEADLINE_DELAY)
    );
    s_swapAutomator.setDeadlineDelay(DEADLINE_DELAY - 1);
  }

  function test_setDeadlineDelay_RevertWhen_NewValueGtMaxThreshold() public {
    vm.expectRevert(
      abi.encodeWithSelector(SwapAutomator.DeadlineDelayTooHigh.selector, MAX_DEADLINE_DELAY + 1, MAX_DEADLINE_DELAY)
    );
    s_swapAutomator.setDeadlineDelay(MAX_DEADLINE_DELAY + 1);
  }

  function test_setDeadlineDelay() public {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.DeadlineDelaySet(NEW_DEADLINE_DELAY);
    s_swapAutomator.setDeadlineDelay(NEW_DEADLINE_DELAY);

    assertEq(s_swapAutomator.getDeadlineDelay(), NEW_DEADLINE_DELAY);
  }
}
