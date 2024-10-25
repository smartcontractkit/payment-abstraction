// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Reserves} from "src/Reserves.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseTest} from "test/BaseTest.t.sol";

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

abstract contract BaseUnitTest is BaseTest {
  SwapAutomator internal s_swapAutomator;
  FeeAggregator internal s_feeAggregatorReceiver;
  FeeAggregator internal s_feeAggregatorSender;
  Reserves internal s_reserves;
  MockERC20 internal s_mockLINK;
  PausableWithAccessControl internal s_contractUnderTest;

  address[] internal s_serviceProviders;
  address[] internal s_contractsPausableWithAccessControl;

  constructor() {
    // Increment block.timestamp to avoid underflows
    skip(1 weeks);

    s_feeAggregatorReceiver = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: MOCK_LINK,
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );

    s_feeAggregatorSender = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: MOCK_LINK,
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );

    s_swapAutomator = new SwapAutomator(
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

    _changePrank(OWNER);
    s_swapAutomator.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_swapAutomator.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);
    s_swapAutomator.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);

    s_feeAggregatorSender.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeAggregatorSender.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);
    s_feeAggregatorSender.grantRole(Roles.BRIDGER_ROLE, BRIDGER);
    s_feeAggregatorSender.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_feeAggregatorReceiver.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeAggregatorReceiver.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);

    s_mockLINK = new MockERC20();
    s_mockLINK.initialize("Link Token", "LINK", 18);

    s_reserves = new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLINK)
      })
    );
    deal(address(s_mockLINK), address(s_reserves), FEE_RESERVE_INITIAL_LINK_BALANCE);

    s_reserves.grantRole(Roles.EARMARK_MANAGER_ROLE, EARMARK_MANAGER);
    s_reserves.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_reserves.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);

    address serviceProvder1 = makeAddr("serviceProvider1");
    address serviceProvder2 = makeAddr("serviceProvider2");

    s_serviceProviders.push(serviceProvder1);
    s_serviceProviders.push(serviceProvder2);

    // Add contracts to the list of contracts that are PausableWithAccessControl
    s_contractsPausableWithAccessControl.push(address(s_feeAggregatorSender));
    s_contractsPausableWithAccessControl.push(address(s_feeAggregatorReceiver));
    s_contractsPausableWithAccessControl.push(address(s_swapAutomator));
    s_contractsPausableWithAccessControl.push(address(s_reserves));

    vm.label(address(s_feeAggregatorSender), "FeeAggregatorSender");
    vm.label(address(s_feeAggregatorReceiver), "FeeAggregatorReceiver");
    vm.label(address(s_swapAutomator), "SwapAutomator");
    vm.label(address(s_reserves), "Reserves");
    vm.label(OWNER, "OWNER");
    vm.label(PAUSER, "PAUSER");
    vm.label(NON_OWNER, "NON_OWNER");
    vm.label(FORWARDER, "FORWARDER");
    vm.label(ASSET_ADMIN, "ASSET_ADMIN");
    vm.label(MOCK_LINK, "MOCK_LINK");
    vm.label(ASSET_1, "ASSET_1");
    vm.label(ASSET_2, "ASSET_2");
    vm.label(INVALID_ASSET, "INVALID_ASSET");
    vm.label(MOCK_CCIP_ROUTER_CLIENT, "MOCK_CCIP_ROUTER_CLIENT");
    vm.label(BRIDGER, "BRIDGER");
    vm.label(ASSET_1_ORACLE, "ASSET_1_ORACLE");
    vm.label(ASSET_2_ORACLE, "ASSET_2_ORACLE");
    vm.label(MOCK_LINK_USD_FEED, "MOCK_LINK_USD_FEED");
    vm.label(EARMARK_MANAGER, "Earmark Manager");
    vm.label(s_serviceProviders[0], "Service Provider 1");
    vm.label(s_serviceProviders[1], "Service Provider 2");
    vm.label(address(s_mockLINK), "Mock LINK");
  }

  /// @notice This modifier sets the contract under test to the next contract in the list of contracts that are
  /// PausableWithAccessControl. This is useful for testing the same functionality across multiple contracts.
  /// @dev This modifier must be applied to all test functions that target the PausableWithAccessControl abstract
  /// contract.
  modifier performForAllContractsPausableWithAccessControl() {
    for (uint256 i = 0; i < s_contractsPausableWithAccessControl.length; i++) {
      s_contractUnderTest = PausableWithAccessControl(s_contractsPausableWithAccessControl[i]);
      _;
    }
  }

  /// @notice Empty test function to ignore file in coverage report
  function test_baseUnitTest() public {}
}
