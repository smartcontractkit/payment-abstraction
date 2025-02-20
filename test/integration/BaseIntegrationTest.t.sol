// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {Reserves} from "src/Reserves.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseTest} from "test/BaseTest.t.sol";

import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {MockUniswapQuoterV2} from "test/mocks/MockUniswapQuoterV2.sol";
import {MockUniswapRouter} from "test/mocks/MockUniswapRouter.sol";
import {MockWrappedNative} from "test/mocks/MockWrappedNative.sol";

import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {MockLinkToken} from "test/mocks/MockLinkToken.sol";

// @notice Base contract for integration tests. Tests the interactions between multiple contracts in a simulated
// environment.
abstract contract BaseIntegrationTest is BaseTest {
  FeeAggregator internal s_feeAggregatorReceiver;
  FeeRouter internal s_feeRouter;
  SwapAutomator internal s_swapAutomator;
  Reserves internal s_reserves;

  MockWrappedNative internal s_mockWETH;
  MockLinkToken internal s_mockLINK;
  MockERC20 internal s_mockUSDC;
  MockERC20 internal s_mockWBTC;

  MockAggregatorV3 internal s_mockLinkUsdFeed;

  MockUniswapRouter internal s_mockUniswapRouter;
  MockUniswapQuoterV2 internal s_mockUniswapQuoterV2;

  address[] internal s_serviceProviders;

  modifier givenAssetIsAllowlisted(
    address asset
  ) {
    (, address msgSender,) = vm.readCallers();

    address[] memory assets = new address[](1);
    assets[0] = asset;

    _changePrank(i_assetAdmin);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);
    _changePrank(msgSender);
    _;
  }

  constructor() {
    // Increment block.timestamp to avoid underflows
    skip(1 weeks);

    s_mockWETH = new MockWrappedNative();
    s_mockLINK = new MockLinkToken();
    s_mockUSDC = new MockERC20();
    s_mockWBTC = new MockERC20();

    s_mockWETH.initialize("WETH", "WETH", 18);
    s_mockUSDC.initialize("USDC", "USDC", 6);
    s_mockWBTC.initialize("WBTC", "WBTC", 8);

    s_mockLinkUsdFeed = new MockAggregatorV3();
    s_mockUniswapRouter = new MockUniswapRouter(address(s_mockLINK));
    s_mockUniswapQuoterV2 = new MockUniswapQuoterV2();

    s_feeAggregatorReceiver = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(s_mockLINK),
        ccipRouterClient: i_mockCCIPRouterClient,
        wrappedNativeToken: address(s_mockWETH)
      })
    );

    s_feeRouter = new FeeRouter(
      FeeRouter.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkToken: address(s_mockLINK),
        wrappedNativeToken: address(s_mockWETH)
      })
    );

    s_swapAutomator = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(s_mockLINK),
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: address(s_mockLinkUsdFeed),
        uniswapRouter: address(s_mockUniswapRouter),
        uniswapQuoterV2: address(s_mockUniswapQuoterV2),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );

    s_reserves = new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(s_mockLINK)
      })
    );

    s_serviceProviders.push(i_serviceProvider1);
    s_serviceProviders.push(i_serviceProvider2);

    vm.startPrank(i_owner);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);
    s_feeAggregatorReceiver.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_feeAggregatorReceiver.grantRole(Roles.WITHDRAWER_ROLE, i_withdrawer);
    s_feeAggregatorReceiver.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomator));
    s_feeAggregatorReceiver.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_feeRouter.grantRole(Roles.BRIDGER_ROLE, i_bridger);
    s_feeRouter.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_feeRouter.grantRole(Roles.WITHDRAWER_ROLE, i_withdrawer);
    s_feeRouter.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_reserves.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_reserves.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_reserves.grantRole(Roles.EARMARK_MANAGER_ROLE, i_earmarkManager);

    // Add contracts to the list of contracts that are EmergencyWithdrawer
    s_commonContracts[CommonContracts.EMERGENCY_WITHDRAWER].push(address(s_feeAggregatorReceiver));
    s_commonContracts[CommonContracts.EMERGENCY_WITHDRAWER].push(address(s_feeRouter));
    s_commonContracts[CommonContracts.EMERGENCY_WITHDRAWER].push(address(s_reserves));

    // Add contracts to the list of contracts that are LinkReceiver
    s_commonContracts[CommonContracts.LINK_RECEIVER].push(address(s_feeAggregatorReceiver));
    s_commonContracts[CommonContracts.LINK_RECEIVER].push(address(s_feeRouter));
    s_commonContracts[CommonContracts.LINK_RECEIVER].push(address(s_reserves));

    vm.label(address(s_feeAggregatorReceiver), "FeeAggregatorReceiver");
    vm.label(address(s_feeRouter), "FeeRouter");
    vm.label(i_owner, "Owner");
    vm.label(i_unpauser, "Unpauser");
    vm.label(i_assetAdmin, "Asset Admin");
    vm.label(address(s_mockLINK), "Mock LINK");
    vm.label(address(s_mockWETH), "Mock WETH");
    vm.label(address(s_mockUSDC), "Mock USDC");
    vm.label(address(s_mockWBTC), "Mock WBTC");
    vm.label(i_mockCCIPRouterClient, "Mock CCIP Router Client");
    vm.label(i_bridger, "Bridger");
    vm.label(i_withdrawer, "Withdrawer");
    vm.label(i_receiver, "Receiver");
    vm.label(address(s_swapAutomator), "SwapAutomator");
    vm.label(address(s_mockLinkUsdFeed), "Mock LINK USD Feed");
    vm.label(address(s_mockUniswapRouter), "Mock Uniswap Router");
    vm.label(address(s_mockUniswapQuoterV2), "Mock Uniswap Quoter V2");
  }

  /// @notice Empty test function to ignore file in coverage report
  function test_baseUnitTest() public {}
}
