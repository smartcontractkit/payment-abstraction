// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract SupportsInterfaceUnitTests is BaseUnitTest {
  function test_supportsInterface() public {
    assertTrue(s_feeAggregatorReceiver.supportsInterface(type(IFeeAggregator).interfaceId));
  }
}
