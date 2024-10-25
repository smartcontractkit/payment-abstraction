// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from
  "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract SupportsInterfaceUnitTests is BaseUnitTest {
  function test_supportsInterface() public performForAllContractsPausableWithAccessControl {
    assertTrue(s_contractUnderTest.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    assertTrue(s_contractUnderTest.supportsInterface(type(IERC165).interfaceId));
    assertTrue(s_contractUnderTest.supportsInterface(type(IAccessControlDefaultAdminRules).interfaceId));
    assertTrue(s_contractUnderTest.supportsInterface(type(IAccessControl).interfaceId));
  }
}
