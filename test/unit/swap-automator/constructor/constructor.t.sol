// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract SwapAutomator_ConstructorUnitTests is BaseUnitTest {
  function test_constructor_RevertWhen_LINKAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(0),
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_FeeAggregatorReceiverAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(0),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_LINKUsdOracleAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: address(0),
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_UniswapRouterAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: address(0),
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_UniswapQuoterV2AddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: address(0),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_DeadlineDelayLtMinThreshold() public {
    vm.expectRevert(
      abi.encodeWithSelector(SwapAutomator.DeadlineDelayTooLow.selector, MIN_DEADLINE_DELAY - 1, MIN_DEADLINE_DELAY)
    );
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: MIN_DEADLINE_DELAY - 1,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_DeadlineDealyGtMaxThreshold() public {
    vm.expectRevert(
      abi.encodeWithSelector(SwapAutomator.DeadlineDelayTooHigh.selector, MAX_DEADLINE_DELAY + 1, MAX_DEADLINE_DELAY)
    );
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: MAX_DEADLINE_DELAY + 1,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor_RevertWhen_LinkReceiverAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: address(0),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: address(0),
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
  }

  function test_constructor() public {
    vm.expectEmit();
    emit SwapAutomator.LinkTokenSet(i_mockLink);
    vm.expectEmit();
    emit SwapAutomator.LINKUsdFeedSet(i_mockLinkUSDFeed);
    vm.expectEmit();
    emit SwapAutomator.UniswapRouterSet(i_mockUniswapRouter);
    vm.expectEmit();
    emit SwapAutomator.UniswapQuoterV2Set(i_mockUniswapQuoterV2);
    vm.expectEmit();
    emit SwapAutomator.FeeAggregatorSet(address(s_feeAggregatorReceiver));
    vm.expectEmit();
    emit SwapAutomator.DeadlineDelaySet(DEADLINE_DELAY);
    vm.expectEmit();
    emit SwapAutomator.LinkReceiverSet(i_receiver);
    vm.expectEmit();
    emit SwapAutomator.MaxPerformDataSizeSet(MAX_PERFORM_DATA_SIZE);

    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: i_mockLink,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: i_mockLinkUSDFeed,
        uniswapRouter: i_mockUniswapRouter,
        uniswapQuoterV2: i_mockUniswapQuoterV2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );
    assertEq(address(s_swapAutomator.getLinkToken()), i_mockLink);
    assertEq(address(s_swapAutomator.getLINKUsdFeed()), i_mockLinkUSDFeed);
    assertEq(address(s_swapAutomator.getFeeAggregator()), address(s_feeAggregatorReceiver));
    assertEq(address(s_swapAutomator.getUniswapRouter()), i_mockUniswapRouter);
    assertEq(address(s_swapAutomator.getUniswapQuoterV2()), i_mockUniswapQuoterV2);
  }

  function test_typeAndVersion() public {
    assertEq(keccak256(bytes(s_swapAutomator.typeAndVersion())), keccak256(bytes("Uniswap V3 Swap Automator 1.0.0")));
  }
}
