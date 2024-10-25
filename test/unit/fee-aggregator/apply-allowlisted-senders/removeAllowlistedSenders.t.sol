// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RemoveAllowlistedSendersUnitTest is BaseUnitTest {
  bytes constant INVALID_SENDER = bytes("123");
  FeeAggregator.AllowlistedSenders[] private s_removedSenders;
  FeeAggregator.AllowlistedSenders[] private s_emptySenders;

  function setUp() public {
    FeeAggregator.AllowlistedSenders memory removedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](2)});
    removedSenders.senders[0] = SENDER_1;
    removedSenders.senders[1] = SENDER_2;
    s_removedSenders.push(removedSenders);

    _changePrank(OWNER);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_removedSenders);
  }

  function test_removeAllowlistedSenders_RevertWhen_SenderIsNotAlreadyAllowlisted() public {
    delete s_removedSenders;
    FeeAggregator.AllowlistedSenders memory removedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    removedSenders.senders[0] = INVALID_SENDER;
    s_removedSenders.push(removedSenders);
    vm.expectRevert(abi.encodeWithSelector(Errors.SenderNotAllowlisted.selector, SOURCE_CHAIN_1, INVALID_SENDER));
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_removedSenders, s_emptySenders);
  }

  function test_removeAllowlistedSenders_SingleSender() external {
    delete s_removedSenders;
    FeeAggregator.AllowlistedSenders memory removedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    removedSenders.senders[0] = SENDER_1;
    s_removedSenders.push(removedSenders);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderRemovedFromAllowlist(SOURCE_CHAIN_1, SENDER_1);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_removedSenders, s_emptySenders);

    bytes[] memory allowlistedSenders = s_feeAggregatorReceiver.getAllowlistedSenders(SOURCE_CHAIN_1);

    assertEq(allowlistedSenders.length, 1);
  }

  function test_removeAllowlistedSenders_MultipleSenders() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderRemovedFromAllowlist(SOURCE_CHAIN_1, SENDER_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderRemovedFromAllowlist(SOURCE_CHAIN_1, SENDER_2);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SourceChainRemovedFromAllowlist(SOURCE_CHAIN_1);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_removedSenders, s_emptySenders);

    bytes[] memory allowlistedSenders = s_feeAggregatorReceiver.getAllowlistedSenders(SOURCE_CHAIN_1);

    assertEq(allowlistedSenders.length, 0);
  }
}
