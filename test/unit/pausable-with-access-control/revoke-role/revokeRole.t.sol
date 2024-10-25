// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControlDefaultAdminRules} from
  "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

contract RevokeRoleUnitTests is BaseUnitTest {
  function setUp() public {
    _changePrank(OWNER);
  }

  function test_revokeRole_RevertWhen_RevokingDefaultAdminRole() public performForAllContractsPausableWithAccessControl {
    vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector);
    s_contractUnderTest.revokeRole(DEFAULT_ADMIN_ROLE, address(this));
  }

  function test_revokeRole_ShouldEnumerateRoleAfterRevoking() public performForAllContractsPausableWithAccessControl {
    s_contractUnderTest.grantRole(TEST_ROLE, PAUSER);
    assertEq(s_contractUnderTest.getRoleMemberCount(TEST_ROLE), 1);
    assertEq(s_contractUnderTest.getRoleMember(TEST_ROLE, 0), PAUSER);
    address[] memory members = new address[](1);
    members[0] = PAUSER;
    assertEq(s_contractUnderTest.getRoleMembers(TEST_ROLE), members);
    s_contractUnderTest.revokeRole(TEST_ROLE, PAUSER);
    assertEq(s_contractUnderTest.getRoleMemberCount(TEST_ROLE), 0);
    assertEq(s_contractUnderTest.getRoleMembers(TEST_ROLE), new address[](0));
  }
}
