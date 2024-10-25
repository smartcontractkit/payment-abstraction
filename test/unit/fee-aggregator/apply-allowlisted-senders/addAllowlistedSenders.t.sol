// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract AddAllowlistedSendersUnitTest is BaseUnitTest {
  FeeAggregator.AllowlistedSenders[] private s_allowlistedSenders;
  FeeAggregator.AllowlistedSenders[] private s_emptySenders;

  function setUp() public {
    FeeAggregator.AllowlistedSenders memory allowlistedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](2)});
    allowlistedSenders.senders[0] = SENDER_1;
    allowlistedSenders.senders[1] = SENDER_2;
    s_allowlistedSenders.push(allowlistedSenders);
  }

  function test_addAllowlistedSenders_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);
  }

  function test_addAllowlistedSenders_RevertWhen_ContractIsPaused()
    public
    givenContractIsPaused(address(s_feeAggregatorReceiver))
  {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);
  }

  function test_addAllowlistedSenders_RevertWhen_SenderIsAlreadyAllowlisted() public {
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);

    vm.expectRevert(
      abi.encodeWithSelector(
        Errors.SenderAlreadyAllowlisted.selector, SOURCE_CHAIN_1, s_allowlistedSenders[0].senders[0]
      )
    );
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);
  }

  function test_addAllowlistedSenders_SingleSender() external {
    delete s_allowlistedSenders;
    FeeAggregator.AllowlistedSenders memory newAllowlistedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    newAllowlistedSenders.senders[0] = SENDER_1;
    s_allowlistedSenders.push(newAllowlistedSenders);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderAddedToAllowlist(SOURCE_CHAIN_1, SENDER_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SourceChainAddedToAllowlist(SOURCE_CHAIN_1);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);

    bytes[] memory allowlistedSenders = s_feeAggregatorReceiver.getAllowlistedSenders(SOURCE_CHAIN_1);
    uint256[] memory allowlistedSourceChains = s_feeAggregatorReceiver.getAllowlistedSourceChains();

    assertTrue(allowlistedSenders.length == 1);
    assertEq(allowlistedSenders[0], SENDER_1);
    assertTrue(allowlistedSourceChains.length == 1);
    assertTrue(allowlistedSourceChains[0] == SOURCE_CHAIN_1);
  }

  function test_addAllowlistedSender_SingleSenderAlreadyAllowlistedSourceChain() external {
    delete s_allowlistedSenders;
    FeeAggregator.AllowlistedSenders memory newAllowlistedSenders =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    newAllowlistedSenders.senders[0] = SENDER_1;
    s_allowlistedSenders.push(newAllowlistedSenders);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);

    delete s_allowlistedSenders;
    FeeAggregator.AllowlistedSenders memory newAllowlistedSenders2 =
      FeeAggregator.AllowlistedSenders({sourceChainSelector: SOURCE_CHAIN_1, senders: new bytes[](1)});
    newAllowlistedSenders2.senders[0] = SENDER_2;
    s_allowlistedSenders.push(newAllowlistedSenders2);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderAddedToAllowlist(SOURCE_CHAIN_1, SENDER_2);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);

    bytes[] memory allowlistedSenders = s_feeAggregatorReceiver.getAllowlistedSenders(SOURCE_CHAIN_1);
    uint256[] memory allowlistedSourceChains = s_feeAggregatorReceiver.getAllowlistedSourceChains();

    assertTrue(allowlistedSenders.length == 2);
    assertEq(allowlistedSenders[0], SENDER_1);
    assertEq(allowlistedSenders[1], SENDER_2);
    assertTrue(allowlistedSourceChains.length == 1);
    assertTrue(allowlistedSourceChains[0] == SOURCE_CHAIN_1);
  }

  function test_addAllowlistedSenders_MultipleSenders() public {
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderAddedToAllowlist(SOURCE_CHAIN_1, SENDER_1);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SenderAddedToAllowlist(SOURCE_CHAIN_1, SENDER_2);
    vm.expectEmit(address(s_feeAggregatorReceiver));
    emit FeeAggregator.SourceChainAddedToAllowlist(SOURCE_CHAIN_1);
    s_feeAggregatorReceiver.applyAllowlistedSenders(s_emptySenders, s_allowlistedSenders);

    bytes[] memory allowlistedSenders = s_feeAggregatorReceiver.getAllowlistedSenders(SOURCE_CHAIN_1);
    uint256[] memory allowlistedSourceChains = s_feeAggregatorReceiver.getAllowlistedSourceChains();

    assertTrue(allowlistedSenders.length == 2);
    assertEq(allowlistedSenders[0], SENDER_1);
    assertEq(allowlistedSenders[1], SENDER_2);
    assertTrue(allowlistedSourceChains.length == 1);
    assertTrue(allowlistedSourceChains[0] == SOURCE_CHAIN_1);
  }
}
