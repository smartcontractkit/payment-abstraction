// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

contract SupportsInterfaceUnitTests is BaseUnitTest {
  function test_supportsInterface() public {
    assertTrue(s_feeAggregatorReceiver.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId));
    assertTrue(s_feeAggregatorReceiver.supportsInterface(type(IFeeAggregator).interfaceId));
  }
}
