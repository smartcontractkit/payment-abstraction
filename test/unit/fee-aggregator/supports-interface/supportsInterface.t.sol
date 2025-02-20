// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

contract SupportsInterfaceUnitTests is BaseUnitTest {
  function test_supportsInterface() public {
    assertTrue(s_feeAggregatorReceiver.supportsInterface(type(IFeeAggregator).interfaceId));
  }

  function test_supportsInterface_UnsupportedIAny2EVMMessageReceiver() public {
    assertFalse(s_feeAggregatorReceiver.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId));
  }
}
