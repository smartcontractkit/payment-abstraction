// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract EmergencyPauseUnitTest is BaseUnitTest {
  function setUp() public {
    _changePrank(i_pauser);
  }

  function test_emergencyPause_RevertWhen_CallerDoesNotHavePAUSER_ROLE()
    public
    performForAllContracts(CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL)
  {
    vm.stopPrank();
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), Roles.PAUSER_ROLE)
    );
    PausableWithAccessControl(s_contractUnderTest).emergencyPause();
  }

  function test_emergencyPause() public performForAllContracts(CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL) {
    vm.expectEmit(address(s_contractUnderTest));
    emit Pausable.Paused(i_pauser);
    PausableWithAccessControl(s_contractUnderTest).emergencyPause();

    assertTrue(PausableWithAccessControl(s_contractUnderTest).paused());
  }
}
