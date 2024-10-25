// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract EmergencyUnpauseUnitTest is BaseUnitTest {
  function setUp() public {
    _changePrank(PAUSER);
  }

  function test_emergencyUnpause_RevertWhen_CallerDoesNotHavePAUSER_ROLE()
    public
    performForAllContractsPausableWithAccessControl
  {
    _changePrank(NON_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, Roles.UNPAUSER_ROLE)
    );
    s_contractUnderTest.emergencyUnpause();
  }

  function test_emergencyUnpause() public performForAllContractsPausableWithAccessControl {
    _changePrank(PAUSER);
    s_contractUnderTest.emergencyPause();
    _changePrank(UNPAUSER);
    vm.expectEmit(address(s_contractUnderTest));
    emit Pausable.Unpaused(UNPAUSER);
    s_contractUnderTest.emergencyUnpause();

    assertFalse(s_contractUnderTest.paused());
  }
}
