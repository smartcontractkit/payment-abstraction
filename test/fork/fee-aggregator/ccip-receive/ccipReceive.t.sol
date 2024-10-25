// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {BaseForkTest} from "test/fork/BaseForkTest.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CCIPReceiveUnitTest is BaseForkTest {
  Client.Any2EVMMessage private s_ccipMessage;

  uint256 private constant BRIDGED_AMOUNT_1 = 1 ether;
  uint256 private constant BRIDGED_AMOUNT_2 = 2 ether;
  bytes32 private constant MESSAGE_ID = keccak256("messageId");

  bytes private s_sender;
  FeeAggregator.AllowlistedSenders[] private s_allowlistedSenders;

  function setUp() public {
    s_sender = abi.encode(address(s_feeAggregatorSender));
    FeeAggregator.AllowlistedSenders memory allowlistedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    FeeAggregator.AllowlistedSenders[] memory emptySenders = new FeeAggregator.AllowlistedSenders[](0);
    allowlistedSenders.senders[0] = s_sender;
    s_allowlistedSenders.push(allowlistedSenders);
    s_feeAggregatorReceiver.applyAllowlistedSenders(emptySenders, s_allowlistedSenders);

    Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
    destTokenAmounts[0] = Client.EVMTokenAmount({token: LINK, amount: BRIDGED_AMOUNT_1});

    s_ccipMessage.messageId = MESSAGE_ID;
    s_ccipMessage.sourceChainSelector = uint64(SOURCE_CHAIN_1);
    s_ccipMessage.sender = abi.encode(address(s_feeAggregatorSender));
    s_ccipMessage.data = bytes("");
    s_ccipMessage.destTokenAmounts.push(destTokenAmounts[0]);

    _deal(LINK, address(s_feeAggregatorReceiver), BRIDGED_AMOUNT_1);
    _changePrank(CCIP_ROUTER);
  }

  function test_ccipReceive_LinkToken() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.AssetReceived(LINK, BRIDGED_AMOUNT_1);

    s_feeAggregatorReceiver.ccipReceive(s_ccipMessage);

    assertEq(IERC20(LINK).balanceOf(address(s_feeAggregatorReceiver)), BRIDGED_AMOUNT_1);
  }
}
