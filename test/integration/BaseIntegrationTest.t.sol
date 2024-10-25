// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {Reserves} from "src/Reserves.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {MockAggregatorV3} from "test/invariants/mocks/MockAggregatorV3.t.sol";
import {MockUniswapQuoterV2} from "test/invariants/mocks/MockUniswapQuoterV2.t.sol";
import {MockUniswapRouter} from "test/invariants/mocks/MockUniswapRouter.t.sol";

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

// @notice Base contract for integration tests. Tests the interactions between multiple contracts in a simulated
// environment.
abstract contract BaseIntegrationTest is BaseTest {
  FeeAggregator internal s_feeAggregatorReceiver;
  FeeRouter internal s_feeRouter;
  SwapAutomator internal s_swapAutomator;
  Reserves internal s_reserves;

  MockERC20 internal s_mockWETH;
  MockERC20 internal s_mockLINK;
  MockERC20 internal s_mockUSDC;
  MockERC20 internal s_mockWBTC;

  MockAggregatorV3 internal s_mockLinkUsdFeed;

  MockUniswapRouter internal s_mockUniswapRouter;
  MockUniswapQuoterV2 internal s_mockUniswapQuoterV2;

  constructor() {
    // Increment block.timestamp to avoid underflows
    skip(1 weeks);

    s_mockWETH = new MockERC20();
    s_mockLINK = new MockERC20();
    s_mockUSDC = new MockERC20();
    s_mockWBTC = new MockERC20();

    s_mockWETH.initialize("WETH", "WETH", 18);
    s_mockLINK.initialize("LINK", "LINK", 18);
    s_mockUSDC.initialize("USDC", "USDC", 6);
    s_mockWBTC.initialize("WBTC", "WBTC", 8);

    s_mockLinkUsdFeed = new MockAggregatorV3();
    s_mockUniswapRouter = new MockUniswapRouter(address(s_mockLINK));
    s_mockUniswapQuoterV2 = new MockUniswapQuoterV2();

    s_feeAggregatorReceiver = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLINK),
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );

    s_feeRouter = new FeeRouter(
      FeeRouter.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        feeAggregator: address(s_feeAggregatorReceiver)
      })
    );

    s_swapAutomator = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLINK),
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: address(s_mockLinkUsdFeed),
        uniswapRouter: address(s_mockUniswapRouter),
        uniswapQuoterV2: address(s_mockUniswapQuoterV2),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );

    s_reserves = new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLINK)
      })
    );

    vm.startPrank(OWNER);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_feeAggregatorReceiver.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeAggregatorReceiver.grantRole(Roles.WITHDRAWER_ROLE, WITHDRAWER);
    s_feeAggregatorReceiver.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomator));
    s_feeAggregatorReceiver.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);
    s_feeRouter.grantRole(Roles.BRIDGER_ROLE, BRIDGER);
    s_feeRouter.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeRouter.grantRole(Roles.WITHDRAWER_ROLE, WITHDRAWER);
    s_reserves.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_reserves.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);

    vm.label(address(s_feeAggregatorReceiver), "FeeAggregatorReceiver");
    vm.label(address(s_feeRouter), "FeeRouter");
    vm.label(OWNER, "OWNER");
    vm.label(PAUSER, "PAUSER");
    vm.label(ASSET_ADMIN, "ASSET_ADMIN");
    vm.label(address(s_mockLINK), "Mock LINK");
    vm.label(address(s_mockWETH), "Mock WETH");
    vm.label(ASSET_2, "ASSET_2");
    vm.label(MOCK_CCIP_ROUTER_CLIENT, "MOCK_CCIP_ROUTER_CLIENT");
    vm.label(BRIDGER, "BRIDGER");
    vm.label(WITHDRAWER, "WITHDRAWER");
    vm.label(RECEIVER, "RECEIVER");
    vm.label(address(s_swapAutomator), "SwapAutomator");
    vm.label(address(s_mockLinkUsdFeed), "Mock LINK USD Feed");
    vm.label(address(s_mockUniswapRouter), "Mock Uniswap Router");
    vm.label(address(s_mockUniswapQuoterV2), "Mock Uniswap Quoter V2");
  }

  /// @notice Empty test function to ignore file in coverage report
  function test_baseUnitTest() public {}
}
