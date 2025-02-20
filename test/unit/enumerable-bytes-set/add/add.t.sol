// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EnumerableBytesSet} from "src/libraries/EnumerableBytesSet.sol";

contract EnumerableBytesSet_AddUnitTest is Test {
  using EnumerableBytesSet for EnumerableBytesSet.BytesSet;

  EnumerableBytesSet.BytesSet private s_set;

  function test_add_SingleValue() public {
    bytes memory value = "value";
    bytes[] memory expected = new bytes[](1);
    expected[0] = value;

    assertFalse(s_set.contains(value));
    assertTrue(s_set.add(value));
    assertEq(s_set.length(), 1);
    assertEq(s_set.at(0), value);
    assertTrue(s_set.contains(value));
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function test_add_MultipleIdenticalValues() public {
    bytes memory value = "value";
    bytes[] memory expected = new bytes[](1);
    expected[0] = value;

    assertTrue(s_set.add(value));
    assertFalse(s_set.add(value));
    assertEq(s_set.length(), 1);
    assertEq(s_set.at(0), value);
    assertTrue(s_set.contains(value));
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function test_add_MultipleUniqueValues() public {
    bytes memory value1 = "value1";
    bytes memory value2 = "value2";
    bytes[] memory expected = new bytes[](2);
    expected[0] = value1;
    expected[1] = value2;

    assertTrue(s_set.add(value1));
    assertTrue(s_set.add(value2));
    assertEq(s_set.length(), 2);
    assertTrue(s_set.contains(value1));
    assertTrue(s_set.contains(value2));
    assertEq(s_set.at(0), value1);
    assertEq(s_set.at(1), value2);
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function testFuzz_add(
    bytes[2] memory values
  ) public {
    bytes[] memory expected = new bytes[](values.length);

    for (uint256 i = 0; i < values.length; ++i) {
      // Ensure uniqueness
      expected[i] = bytes.concat(values[i], abi.encodePacked(i));
      s_set.add(expected[i]);
      assertEq(s_set.at(i), expected[i]);
      assertTrue(s_set.contains(expected[i]));
    }

    assertEq(s_set.length(), values.length);
    _assertBytesArrayEq(s_set.values(), expected);
  }

  function _assertBytesArrayEq(bytes[] memory a, bytes[] memory b) internal {
    assertEq(a.length, b.length);
    for (uint256 i = 0; i < a.length; i++) {
      assertEq(a[i], b[i]);
    }
  }
}
