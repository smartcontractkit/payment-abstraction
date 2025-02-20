// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RemoveAllowlistedReceiversUnitTest is BaseUnitTest {
  bytes constant INVALID_i_receiver = bytes("123");

  function setUp() public {
    FeeAggregator.AllowlistedReceivers[] memory removedReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory removedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    removedReceiver.receivers[0] = RECEIVER_1;
    removedReceiver.receivers[1] = RECEIVER_2;
    removedReceivers[0] = removedReceiver;

    _changePrank(i_owner);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, removedReceivers);
  }

  function test_removeAllowlistedReceivers_RevertWhen_ReceiverIsNotAlreadyAllowlisted() public {
    FeeAggregator.AllowlistedReceivers[] memory removedReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory removedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](1)});
    removedReceiver.receivers[0] = INVALID_i_receiver;
    removedReceivers[0] = removedReceiver;

    vm.expectRevert(
      abi.encodeWithSelector(FeeAggregator.ReceiverNotAllowlisted.selector, SOURCE_CHAIN_1, INVALID_i_receiver)
    );
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(removedReceivers, emptyReceivers);
  }

  function test_removeAllowlistedReceivers_SingleReceiver() external {
    FeeAggregator.AllowlistedReceivers[] memory removedReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory removedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](1)});
    removedReceiver.receivers[0] = RECEIVER_1;
    removedReceivers[0] = removedReceiver;

    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.ReceiverRemovedFromAllowlist(SOURCE_CHAIN_1, RECEIVER_1);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(removedReceivers, emptyReceivers);

    bytes[] memory allowlistedReceivers = s_feeAggregatorReceiver.getAllowlistedReceivers(SOURCE_CHAIN_1);

    assertEq(allowlistedReceivers.length, 1);
  }

  function test_removeAllowlistedReceivers_MultipleReceivers() public {
    FeeAggregator.AllowlistedReceivers[] memory removedReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory removedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    removedReceiver.receivers[0] = RECEIVER_1;
    removedReceiver.receivers[1] = RECEIVER_2;
    removedReceivers[0] = removedReceiver;

    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.ReceiverRemovedFromAllowlist(SOURCE_CHAIN_1, RECEIVER_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.ReceiverRemovedFromAllowlist(SOURCE_CHAIN_1, RECEIVER_2);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.DestinationChainRemovedFromAllowlist(SOURCE_CHAIN_1);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(removedReceivers, emptyReceivers);

    bytes[] memory allowlistedReceivers = s_feeAggregatorReceiver.getAllowlistedReceivers(SOURCE_CHAIN_1);

    assertEq(allowlistedReceivers.length, 0);
  }
}
