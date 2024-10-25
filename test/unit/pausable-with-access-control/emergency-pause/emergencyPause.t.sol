// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract EmergencyPauseUnitTest is BaseUnitTest {
  function setUp() public {
    _changePrank(PAUSER);
  }

  function test_emergencyPause_RevertWhen_CallerDoesNotHavePAUSER_ROLE()
    public
    performForAllContractsPausableWithAccessControl
  {
    vm.stopPrank();
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), Roles.PAUSER_ROLE)
    );
    s_contractUnderTest.emergencyPause();
  }

  function test_emergencyPause() public performForAllContractsPausableWithAccessControl {
    vm.expectEmit(address(s_contractUnderTest));
    emit Pausable.Paused(PAUSER);
    s_contractUnderTest.emergencyPause();

    assertTrue(s_contractUnderTest.paused());
  }
}
