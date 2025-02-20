//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SwapAutomator_SetMaxPerformDataSizeUnitTest is BaseUnitTest {
  uint256 private constant NEW_MAX_PERFORM_DATA_SIZE = 3000;

  function test_setMaxPerformDataSize_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_nonOwner, DEFAULT_ADMIN_ROLE)
    );
    s_swapAutomator.setMaxPerformDataSize(NEW_MAX_PERFORM_DATA_SIZE);
  }

  function test_setMaxPerformDataSize_RevertWhen_NewMaxPerformDataSizeEqZero() public {
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_swapAutomator.setMaxPerformDataSize(0);
  }

  function test_setMaxPerformDataSize_RevertWhen_NewMaxPerformaDataSizeEqOldMaxPerformDataSize() public {
    vm.expectRevert(Errors.ValueNotUpdated.selector);
    s_swapAutomator.setMaxPerformDataSize(MAX_PERFORM_DATA_SIZE);
  }

  function test_setMaxPerformDataSize() public {
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.MaxPerformDataSizeSet(NEW_MAX_PERFORM_DATA_SIZE);

    s_swapAutomator.setMaxPerformDataSize(NEW_MAX_PERFORM_DATA_SIZE);

    assertEq(s_swapAutomator.getMaxPerformDataSize(), NEW_MAX_PERFORM_DATA_SIZE);
  }
}
