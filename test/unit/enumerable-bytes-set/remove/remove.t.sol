// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EnumerableBytesSet} from "src/libraries/EnumerableBytesSet.sol";

contract EnumerableBytesSet_RemoveUnitTest is Test {
  using EnumerableBytesSet for EnumerableBytesSet.BytesSet;

  EnumerableBytesSet.BytesSet private s_set;

  function setUp() public {
    s_set.add("value1");
    s_set.add("value2");
  }

  function test_remove_SingleExistingValue() public {
    bytes memory value = "value1";
    bytes[] memory expected = new bytes[](1);
    expected[0] = "value2";

    assertTrue(s_set.remove(value));
    assertEq(s_set.length(), 1);
    assertFalse(s_set.contains(value));
    assertEq(s_set.at(0), "value2");
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function test_remove_MultipleExistingValues() public {
    bytes memory value1 = "value1";
    bytes memory value2 = "value2";
    bytes[] memory expected = new bytes[](0);

    assertEq(s_set.at(0), "value1");
    assertEq(s_set.at(1), "value2");
    assertTrue(s_set.remove(value1));
    assertTrue(s_set.remove(value2));
    assertEq(s_set.length(), 0);
    assertFalse(s_set.contains(value1));
    assertFalse(s_set.contains(value2));
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function test_remove_SingleNonExistingValue() public {
    bytes memory value = "value3";
    bytes[] memory expected = new bytes[](2);
    expected[0] = "value1";
    expected[1] = "value2";

    assertFalse(s_set.remove(value));
    assertEq(s_set.length(), 2);
    assertFalse(s_set.contains(value));
    assertEq(s_set.at(0), "value1");
    assertEq(s_set.at(1), "value2");
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function _assertBytesArrayEq(bytes[] memory a, bytes[] memory b) internal {
    assertEq(a.length, b.length);
    for (uint256 i = 0; i < a.length; i++) {
      assertEq(a[i], b[i]);
    }
  }
}
