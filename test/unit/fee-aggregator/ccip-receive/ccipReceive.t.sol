// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract CCIPReceiveUnitTest is BaseUnitTest {
  Client.Any2EVMMessage private s_ccipMessage;

  uint256 private constant BRIDGED_AMOUNT_1 = 1 ether;
  uint256 private constant BRIDGED_AMOUNT_2 = 2 ether;
  bytes32 private constant MESSAGE_ID = keccak256("messageId");

  bytes private s_sender;
  FeeAggregator.AllowlistedSenders[] private s_allowlistedSenders;
  FeeAggregator.AllowlistedSenders[] private s_emptySenders;

  function setUp() public {
    s_sender = abi.encode(address(s_feeAggregatorSender));
    FeeAggregator.AllowlistedSenders memory allowlistedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    allowlistedSenders.senders[0] = s_sender;
    s_allowlistedSenders.push(allowlistedSenders);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);

    Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](2);

    destTokenAmounts[0] = Client.EVMTokenAmount({token: ASSET_1, amount: BRIDGED_AMOUNT_1});
    destTokenAmounts[1] = Client.EVMTokenAmount({token: ASSET_2, amount: BRIDGED_AMOUNT_2});

    s_ccipMessage.messageId = MESSAGE_ID;
    s_ccipMessage.sourceChainSelector = uint64(SOURCE_CHAIN_1);
    s_ccipMessage.sender = abi.encode(address(s_feeAggregatorSender));
    s_ccipMessage.data = bytes("");
    s_ccipMessage.destTokenAmounts.push(destTokenAmounts[0]);
    s_ccipMessage.destTokenAmounts.push(destTokenAmounts[1]);

    _changePrank(MOCK_CCIP_ROUTER_CLIENT);
  }

  function test_ccipReceive_RevertWhen_SenderIsNotAllowlisted() public {
    s_ccipMessage.sender = abi.encode(address(this));
    vm.expectRevert(abi.encodeWithSelector(Errors.SenderNotAllowlisted.selector, SOURCE_CHAIN_1, s_ccipMessage.sender));
    s_feeAggregatorReceiver.ccipReceive(s_ccipMessage);
  }

  function test_ccipReceive_SingleAsset() public {
    s_ccipMessage.destTokenAmounts.pop();
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetReceived(ASSET_1, BRIDGED_AMOUNT_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.MessageReceived(s_sender, SOURCE_CHAIN_1, MESSAGE_ID);

    s_feeAggregatorReceiver.ccipReceive(s_ccipMessage);
  }

  function test_ccipReceive_MultipleAssets() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetReceived(ASSET_1, BRIDGED_AMOUNT_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetReceived(ASSET_2, BRIDGED_AMOUNT_2);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.MessageReceived(s_sender, SOURCE_CHAIN_1, MESSAGE_ID);

    s_feeAggregatorReceiver.ccipReceive(s_ccipMessage);
  }
}
