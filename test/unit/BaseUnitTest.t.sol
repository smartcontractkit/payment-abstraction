// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Reserves} from "src/Reserves.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseTest} from "test/BaseTest.t.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

abstract contract BaseUnitTest is BaseTest {
  address internal immutable i_asset1 = makeAddr("asset1");
  address internal immutable i_asset2 = makeAddr("asset2");
  address internal immutable i_token1 = makeAddr("token1");
  address internal immutable i_token2 = makeAddr("token2");
  address internal immutable i_mockLink = makeAddr("mockLink");
  address internal immutable i_asset1UsdFeed = makeAddr("asset1UsdFeed");
  address internal immutable i_asset2UsdFeed = makeAddr("asset2UsdFeed");
  address internal immutable i_mockLinkUSDFeed = makeAddr("mockLinkUSDFeed");
  address internal immutable i_mockUniswapRouter = makeAddr("mockUniswapRouter");
  address internal immutable i_mockUniswapQuoterV2 = makeAddr("mockUniswapQuoterV2");

  SwapAutomator internal s_swapAutomator;
  FeeAggregator internal s_feeAggregatorReceiver;
  FeeAggregator internal s_feeAggregatorSender;
  FeeRouter internal s_feeRouter;
  Reserves internal s_reserves;

  address internal s_mockWrappedNativeToken = makeAddr("mockWrappedNativeToken");

  address[] internal s_serviceProviders;

  constructor() {
    // Increment block.timestamp to avoid underflows
    skip(1 weeks);

    s_feeAggregatorReceiver = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: i_mockLink,
        ccipRouterClient: i_mockCCIPRouterClient,
        wrappedNativeToken: s_mockWrappedNativeToken
      })
    );

    s_feeAggregatorSender = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: i_mockLink,
        ccipRouterClient: i_mockCCIPRouterClient,
        wrappedNativeToken: s_mockWrappedNativeToken
      })
    );

    s_feeRouter = new FeeRouter(
      FeeRouter.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkToken: i_mockLink,
        wrappedNativeToken: makeAddr("WrappedNativeToken")
      })
    );

    vm.mockCall(i_mockLink, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    vm.mockCall(i_mockLinkUSDFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8));

    s_swapAutomator = new SwapAutomator(
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

    _changePrank(i_owner);
    s_swapAutomator.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_swapAutomator.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_swapAutomator.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);

    s_feeAggregatorSender.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_feeAggregatorSender.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_feeAggregatorSender.grantRole(Roles.BRIDGER_ROLE, i_bridger);
    s_feeAggregatorSender.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);
    s_feeAggregatorReceiver.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_feeAggregatorReceiver.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);

    s_reserves = new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(i_mockLink)
      })
    );

    s_reserves.grantRole(Roles.EARMARK_MANAGER_ROLE, i_earmarkManager);
    s_reserves.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_reserves.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);

    s_serviceProviders.push(i_serviceProvider1);
    s_serviceProviders.push(i_serviceProvider2);

    // Add contracts to the list of contracts that are PausableWithAccessControl
    s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_feeAggregatorSender));
    s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_feeAggregatorReceiver));
    s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_swapAutomator));
    s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_reserves));

    vm.label(address(s_feeAggregatorSender), "FeeAggregatorSender");
    vm.label(address(s_feeAggregatorReceiver), "FeeAggregatorReceiver");
    vm.label(address(s_feeRouter), "FeeRouter");
    vm.label(address(s_swapAutomator), "SwapAutomator");
    vm.label(address(s_reserves), "Reserves");
    vm.label(i_owner, "Owner");
    vm.label(i_unpauser, "Unpauser");
    vm.label(i_nonOwner, "Non-Owner");
    vm.label(i_forwarder, "Forwarder");
    vm.label(i_assetAdmin, "Asset Admin");
    vm.label(i_mockLink, "Mock LINK");
    vm.label(i_asset1, "Asset 1");
    vm.label(i_asset2, "Asset 2");
    vm.label(i_invalidAsset, "Invalid Asset");
    vm.label(i_mockCCIPRouterClient, "Mock CCIP Router Client");
    vm.label(i_bridger, "Bridger");
    vm.label(i_asset1UsdFeed, "Asset 1 USD Feed");
    vm.label(i_asset2UsdFeed, "Asset 2 USD Feed");
    vm.label(i_mockLinkUSDFeed, "Mock LINK/USD Feed");
    vm.label(i_earmarkManager, "Earmark Manager");
    vm.label(s_serviceProviders[0], "Service Provider 1");
    vm.label(s_serviceProviders[1], "Service Provider 2");
  }

  /// @notice Empty test function to ignore file in coverage report
  function test_baseUnitTest() public {}
}
