// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract ConstructorUnitTests is BaseUnitTest {
  function test_constructor_RevertWhen_LINKAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(0),
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );
  }

  function test_constructor_RevertWhen_FeeAggregatorReceiverAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(0),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );
  }

  function test_constructor_RevertWhen_LINKUsdOracleAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: address(0),
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );
  }

  function test_constructor_RevertWhen_UniswapRouterAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: address(0),
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );
  }

  function test_constructor_RevertWhen_UniswapQuoterV2AddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: address(0),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
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
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: MIN_DEADLINE_DELAY - 1,
        linkReceiver: RECEIVER
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
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: MAX_DEADLINE_DELAY + 1,
        linkReceiver: RECEIVER
      })
    );
  }

  function test_constructor_RevertWhen_LinkReceiverAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: address(0),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: address(0)
      })
    );
  }

  function test_constructor() public {
    vm.expectEmit();
    emit SwapAutomator.FeeAggregatorSet(address(s_feeAggregatorReceiver));
    vm.expectEmit();
    emit SwapAutomator.DeadlineDelaySet(DEADLINE_DELAY);
    vm.expectEmit();
    emit SwapAutomator.LinkReceiverSet(RECEIVER);
    vm.expectEmit();
    emit SwapAutomator.LinkTokenSet(MOCK_LINK);
    vm.expectEmit();
    emit SwapAutomator.LINKUsdFeedSet(MOCK_LINK_USD_FEED);
    vm.expectEmit();
    emit SwapAutomator.UniswapRouterSet(MOCK_UNISWAP_ROUTER);
    vm.expectEmit();
    emit SwapAutomator.UniswapQuoterV2Set(MOCK_UNISWAP_QUOTER_V2);

    new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: MOCK_LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: MOCK_LINK_USD_FEED,
        uniswapRouter: MOCK_UNISWAP_ROUTER,
        uniswapQuoterV2: MOCK_UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );
    assertEq(address(s_swapAutomator.getLinkToken()), MOCK_LINK);
    assertEq(address(s_swapAutomator.getLINKUsdFeed()), MOCK_LINK_USD_FEED);
    assertEq(address(s_swapAutomator.getFeeAggregator()), address(s_feeAggregatorReceiver));
    assertEq(address(s_swapAutomator.getUniswapRouter()), MOCK_UNISWAP_ROUTER);
    assertEq(address(s_swapAutomator.getUniswapQuoterV2()), MOCK_UNISWAP_QUOTER_V2);
  }

  function test_typeAndVersion() public {
    assertEq(keccak256(bytes(s_swapAutomator.typeAndVersion())), keccak256(bytes("Uniswap V3 Swap Automator 1.0.0")));
  }
}
