// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract AddAllowlistedReceiversUnitTest is BaseUnitTest {
  function setUp() public {}

  function test_addAllowlistedReceivers_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    allowlistedReceiver.receivers[0] = RECEIVER_1;
    allowlistedReceiver.receivers[1] = RECEIVER_2;
    newReceivers[0] = allowlistedReceiver;

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);
  }

  function test_addAllowlistedReceivers_RevertWhen_ContractIsPaused()
    public
    givenContractIsPaused(address(s_feeAggregatorReceiver))
  {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    allowlistedReceiver.receivers[0] = RECEIVER_1;
    allowlistedReceiver.receivers[1] = RECEIVER_2;
    newReceivers[0] = allowlistedReceiver;

    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);
  }

  function test_addAllowlistedReceivers_RevertWhen_ReceiverIsAlreadyAllowlisted() public {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    allowlistedReceiver.receivers[0] = RECEIVER_1;
    allowlistedReceiver.receivers[1] = RECEIVER_2;
    newReceivers[0] = allowlistedReceiver;

    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);

    vm.expectRevert(
      abi.encodeWithSelector(
        FeeAggregator.ReceiverAlreadyAllowlisted.selector, DESTINATION_CHAIN_1, newReceivers[0].receivers[0]
      )
    );
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);
  }

  function test_addAllowlistedReceivers_RevertWhen_ReceiverIsZeroBytes() public {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](1)});
    newReceivers[0] = allowlistedReceiver;

    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);
  }

  function test_addAllowlistedReceivers_RevertWhen_ReceiverIsZeroBytes32Address() public {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](1)});
    allowlistedReceiver.receivers[0] = abi.encode(address(0));
    newReceivers[0] = allowlistedReceiver;

    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);
  }

  function test_addAllowlistedReceivers_RevertWhen_ChainSelectorIsZero() public {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: 0, receivers: new bytes[](1)});
    allowlistedReceiver.receivers[0] = abi.encode(address(1));
    newReceivers[0] = allowlistedReceiver;

    vm.expectRevert(FeeAggregator.InvalidChainSelector.selector);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);
  }

  function test_addAllowlistedReceivers_EmptyLists() external {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    vm.recordLogs();
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(newReceivers, newReceivers);
    assertEq(vm.getRecordedLogs().length, 0);
  }

  function test_addAllowlistedReceivers_SingleReceiver() external {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory newAllowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: DESTINATION_CHAIN_1, receivers: new bytes[](1)});
    newAllowlistedReceiver.receivers[0] = RECEIVER_1;
    newReceivers[0] = newAllowlistedReceiver;

    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.ReceiverAddedToAllowlist(DESTINATION_CHAIN_1, RECEIVER_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.DestinationChainAddedToAllowlist(DESTINATION_CHAIN_1);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);

    bytes[] memory allowlistedReceivers = s_feeAggregatorReceiver.getAllowlistedReceivers(DESTINATION_CHAIN_1);
    uint256[] memory allowlistedDestinationChains = s_feeAggregatorReceiver.getAllowlistedDestinationChains();

    assertTrue(allowlistedReceivers.length == 1);
    assertEq(allowlistedReceivers[0], RECEIVER_1);
    assertTrue(allowlistedDestinationChains.length == 1);
    assertTrue(allowlistedDestinationChains[0] == DESTINATION_CHAIN_1);
  }

  function test_addAllowlistedReceiver_ReceiverAlreadyAllowlistedDestinationChain() external {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory newAllowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: DESTINATION_CHAIN_1, receivers: new bytes[](1)});
    newAllowlistedReceiver.receivers[0] = RECEIVER_1;
    newReceivers[0] = newAllowlistedReceiver;

    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);

    delete newReceivers[0];
    FeeAggregator.AllowlistedReceivers memory newAllowlistedReceiver2 =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: DESTINATION_CHAIN_1, receivers: new bytes[](1)});
    newAllowlistedReceiver2.receivers[0] = RECEIVER_2;
    newReceivers[0] = newAllowlistedReceiver2;

    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.ReceiverAddedToAllowlist(DESTINATION_CHAIN_1, RECEIVER_2);
    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);

    bytes[] memory allowlistedReceivers = s_feeAggregatorReceiver.getAllowlistedReceivers(DESTINATION_CHAIN_1);
    uint256[] memory allowlistedDestinationChains = s_feeAggregatorReceiver.getAllowlistedDestinationChains();

    assertTrue(allowlistedReceivers.length == 2);
    assertEq(allowlistedReceivers[0], RECEIVER_1);
    assertEq(allowlistedReceivers[1], RECEIVER_2);
    assertTrue(allowlistedDestinationChains.length == 1);
    assertTrue(allowlistedDestinationChains[0] == DESTINATION_CHAIN_1);
  }

  function test_addAllowlistedReceivers_MultipleReceivers() public {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    allowlistedReceiver.receivers[0] = RECEIVER_1;
    allowlistedReceiver.receivers[1] = RECEIVER_2;
    newReceivers[0] = allowlistedReceiver;

    vm.expectEmit(true, false, false, true);
    emit FeeAggregator.ReceiverAddedToAllowlist(DESTINATION_CHAIN_1, RECEIVER_1);

    vm.expectEmit(true, false, false, true);
    emit FeeAggregator.ReceiverAddedToAllowlist(DESTINATION_CHAIN_1, RECEIVER_2);

    vm.expectEmit(true, false, false, true);
    emit FeeAggregator.DestinationChainAddedToAllowlist(DESTINATION_CHAIN_1);

    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);

    bytes[] memory allowlistedReceivers = s_feeAggregatorReceiver.getAllowlistedReceivers(DESTINATION_CHAIN_1);
    uint256[] memory allowlistedDestinationChains = s_feeAggregatorReceiver.getAllowlistedDestinationChains();

    assertEq(allowlistedReceivers.length, 2, "Incorrect number of allowlisted receivers");
    assertEq(allowlistedReceivers[0], RECEIVER_1, "First receiver mismatch");
    assertEq(allowlistedReceivers[1], RECEIVER_2, "Second receiver mismatch");

    assertEq(allowlistedDestinationChains.length, 1, "Incorrect number of allowlisted destination chains");
    assertEq(allowlistedDestinationChains[0], DESTINATION_CHAIN_1, "Destination chain mismatch");
  }

  function test_addAndRemoveAllowlistedReceiver() public {
    FeeAggregator.AllowlistedReceivers[] memory newReceivers = new FeeAggregator.AllowlistedReceivers[](1);
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    FeeAggregator.AllowlistedReceivers memory allowlistedReceiver =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: SOURCE_CHAIN_1, receivers: new bytes[](2)});
    allowlistedReceiver.receivers[0] = RECEIVER_1;
    allowlistedReceiver.receivers[1] = RECEIVER_2;
    newReceivers[0] = allowlistedReceiver;

    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(emptyReceivers, newReceivers);

    FeeAggregator.AllowlistedReceivers[] memory receiversToAdd = new FeeAggregator.AllowlistedReceivers[](1);
    receiversToAdd[0] =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: DESTINATION_CHAIN_1, receivers: new bytes[](1)});
    receiversToAdd[0].receivers[0] = RECEIVER_3;

    FeeAggregator.AllowlistedReceivers[] memory receiversToRemove = new FeeAggregator.AllowlistedReceivers[](1);
    receiversToRemove[0] =
      FeeAggregator.AllowlistedReceivers({remoteChainSelector: DESTINATION_CHAIN_1, receivers: new bytes[](1)});
    receiversToRemove[0].receivers[0] = RECEIVER_1;

    vm.expectEmit(true, false, false, true);
    emit FeeAggregator.ReceiverRemovedFromAllowlist(DESTINATION_CHAIN_1, RECEIVER_1);

    vm.expectEmit(true, false, false, true);
    emit FeeAggregator.ReceiverAddedToAllowlist(DESTINATION_CHAIN_1, RECEIVER_3);

    s_feeAggregatorReceiver.applyAllowlistedReceiverUpdates(receiversToRemove, receiversToAdd);

    bytes[] memory allowlistedReceivers = s_feeAggregatorReceiver.getAllowlistedReceivers(DESTINATION_CHAIN_1);
    uint256[] memory allowlistedDestinationChains = s_feeAggregatorReceiver.getAllowlistedDestinationChains();

    assertEq(allowlistedReceivers.length, 2, "Should have two allowlisted receivers");
    assertEq(allowlistedReceivers[0], RECEIVER_2, "First receiver should be RECEIVER_2");
    assertEq(allowlistedReceivers[1], RECEIVER_3, "Second receiver should be RECEIVER_3");

    assertEq(allowlistedDestinationChains.length, 1, "Should have one allowlisted destination chain");
    assertEq(allowlistedDestinationChains[0], DESTINATION_CHAIN_1, "Destination chain should be DESTINATION_CHAIN_1");
  }
}
