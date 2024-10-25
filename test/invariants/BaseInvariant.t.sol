// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Reserves} from "src/Reserves.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {AssetHandler} from "test/invariants/handlers/AssetHandler.t.sol";
import {ReservesHandler} from "test/invariants/handlers/ReservesHandler.t.sol";
import {UpkeepHandler} from "test/invariants/handlers/UpkeepHandler.t.sol";
import {MockAggregatorV3} from "test/invariants/mocks/MockAggregatorV3.t.sol";
import {MockUniswapQuoterV2} from "test/invariants/mocks/MockUniswapQuoterV2.t.sol";
import {MockUniswapRouter} from "test/invariants/mocks/MockUniswapRouter.t.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

abstract contract BaseInvariant is StdInvariant, BaseTest {
  FeeAggregator internal s_feeAggregatorReceiver;
  FeeAggregator internal s_feeAggregatorSender;
  Reserves internal s_reserves;
  SwapAutomator internal s_swapAutomator;

  AssetHandler internal s_assetHandler;
  ReservesHandler internal s_reservesHandler;
  UpkeepHandler internal s_upkeepHandler;

  MockERC20 internal s_mockLink;
  MockERC20 internal s_mockWeth;
  MockERC20 internal s_mockUsdc;
  MockERC20 internal s_mockHighDecimalToken;

  MockAggregatorV3 internal s_mockLinkUsdFeed;
  MockAggregatorV3 internal s_mockEthUsdFeed;
  MockAggregatorV3 internal s_mockUsdcUsdFeed;
  MockAggregatorV3 internal s_mockHdtUsdFeed;

  MockUniswapRouter internal s_mockUniswapRouter;
  MockUniswapQuoterV2 internal s_mockUniswapQuoterV2;

  function setUp() public {
    // Increment block.timestamp to avoid underflows
    skip(1 weeks);

    s_mockLink = new MockERC20();
    s_mockWeth = new MockERC20();
    s_mockUsdc = new MockERC20();
    s_mockHighDecimalToken = new MockERC20();

    s_mockLink.initialize("Chainlink", "LINK", 18);
    s_mockWeth.initialize("Wrapped Ether", "WETH", 18);
    s_mockUsdc.initialize("USDC", "USDC", 6);
    s_mockHighDecimalToken.initialize("High Decimal Token", "HDT", 20);

    s_mockLinkUsdFeed = new MockAggregatorV3();
    s_mockEthUsdFeed = new MockAggregatorV3();
    s_mockUsdcUsdFeed = new MockAggregatorV3();
    s_mockHdtUsdFeed = new MockAggregatorV3();

    s_mockLinkUsdFeed.transmit(20e8);
    s_mockEthUsdFeed.transmit(4_000e8);
    s_mockUsdcUsdFeed.transmit(1e8);
    s_mockHdtUsdFeed.transmit(1_000e8);

    s_feeAggregatorReceiver = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: address(s_mockLink),
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );

    s_feeAggregatorSender = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: address(s_mockLink),
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );

    s_reserves = new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLink)
      })
    );
    address[] memory serviceProviders = new address[](3);
    serviceProviders[0] = SERVICE_PROVIDER_1;
    serviceProviders[1] = SERVICE_PROVIDER_2;
    serviceProviders[2] = SERVICE_PROVIDER_3;

    s_mockUniswapRouter = new MockUniswapRouter(address(s_mockLink));
    s_mockUniswapQuoterV2 = new MockUniswapQuoterV2();

    s_swapAutomator = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLink),
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: address(s_mockLinkUsdFeed),
        uniswapRouter: address(s_mockUniswapRouter),
        uniswapQuoterV2: address(s_mockUniswapQuoterV2),
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );

    s_assetHandler = new AssetHandler(s_feeAggregatorReceiver, s_swapAutomator);
    s_reservesHandler = new ReservesHandler(s_reserves, s_mockLink, serviceProviders);
    s_upkeepHandler = new UpkeepHandler(
      s_feeAggregatorReceiver,
      s_swapAutomator,
      s_mockUniswapRouter,
      s_mockUniswapQuoterV2,
      s_mockLinkUsdFeed,
      s_mockLink
    );

    _changePrank(OWNER);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, address(s_assetHandler));
    s_feeAggregatorReceiver.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomator));
    s_feeAggregatorSender.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeAggregatorSender.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomator));
    s_reserves.grantRole(Roles.EARMARK_MANAGER_ROLE, EARMARK_MANAGER);
    s_swapAutomator.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_swapAutomator.grantRole(Roles.ASSET_ADMIN_ROLE, address(s_assetHandler));
    s_swapAutomator.setForwarder(address(s_upkeepHandler));

    address[] memory swapAssets = new address[](3);
    SwapAutomator.SwapParams[] memory swapParams = new SwapAutomator.SwapParams[](3);
    swapAssets[0] = address(s_mockWeth);
    swapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(address(s_mockEthUsdFeed)),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION_INVARIANTS,
      swapInterval: 0,
      path: bytes.concat(bytes20(address(s_mockWeth)), bytes3(UNI_POOL_FEE), bytes20(address(s_mockLink)))
    });
    swapAssets[1] = address(s_mockUsdc);
    swapParams[1] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(address(s_mockUsdcUsdFeed)),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION_INVARIANTS,
      swapInterval: 0,
      path: bytes.concat(bytes20(address(s_mockUsdc)), bytes3(UNI_POOL_FEE), bytes20(address(s_mockLink)))
    });
    swapAssets[2] = address(s_mockHighDecimalToken);
    swapParams[2] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(address(s_mockHdtUsdFeed)),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION_INVARIANTS,
      swapInterval: 0,
      path: bytes.concat(bytes20(address(s_mockHighDecimalToken)), bytes3(UNI_POOL_FEE), bytes20(address(s_mockLink)))
    });

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorReceiver.applyAllowlistedAssets(new address[](0), swapAssets);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: swapAssets, assetsSwapParams: swapParams})
    );

    _changePrank(EARMARK_MANAGER);
    s_reserves.addAllowlistedServiceProviders(serviceProviders);

    bytes4[] memory assetHanderSelectors = new bytes4[](1);
    assetHanderSelectors[0] = s_assetHandler.setAssetSwapParams.selector;

    bytes4[] memory reservesHandlerSelectors = new bytes4[](2);
    reservesHandlerSelectors[0] = s_reservesHandler.setEarmarks.selector;
    reservesHandlerSelectors[1] = s_reservesHandler.withdraw.selector;

    bytes4[] memory upkeepHandlerSelectors = new bytes4[](1);
    upkeepHandlerSelectors[0] = s_upkeepHandler.performUpkeep.selector;

    targetSelector(FuzzSelector({addr: address(s_assetHandler), selectors: assetHanderSelectors}));
    targetSelector(FuzzSelector({addr: address(s_reservesHandler), selectors: reservesHandlerSelectors}));
    targetSelector(FuzzSelector({addr: address(s_upkeepHandler), selectors: upkeepHandlerSelectors}));

    excludeContract(address(s_feeAggregatorReceiver));
    excludeContract(address(s_feeAggregatorSender));
    excludeContract(address(s_reserves));
    excludeContract(address(s_swapAutomator));
    excludeContract(address(s_mockLink));
    excludeContract(address(s_mockWeth));
    excludeContract(address(s_mockUsdc));
    excludeContract(address(s_mockHighDecimalToken));
    excludeContract(address(s_mockLinkUsdFeed));
    excludeContract(address(s_mockEthUsdFeed));
    excludeContract(address(s_mockUsdcUsdFeed));
    excludeContract(address(s_mockHdtUsdFeed));
    excludeContract(address(s_mockUniswapRouter));
    excludeContract(address(s_assetHandler));
    excludeContract(address(s_reservesHandler));
    excludeContract(address(s_mockUniswapQuoterV2));

    vm.label(address(s_feeAggregatorReceiver), "FeeAggregatorReceiver");
    vm.label(address(s_feeAggregatorSender), "FeeAggregatorSender");
    vm.label(address(s_swapAutomator), "SwapAutomator");
    vm.label(address(s_reserves), "Reserves");
    vm.label(OWNER, "OWNER");
    vm.label(ASSET_ADMIN, "ASSET_ADMIN");
    vm.label(address(s_mockLink), "LINK");
    vm.label(address(s_mockWeth), "WETH");
    vm.label(address(s_mockUsdc), "USDC");
    vm.label(address(s_mockHighDecimalToken), "HDT");
    vm.label(address(s_mockLinkUsdFeed), "MOCK_LINK_USD_FEED");
    vm.label(address(s_mockEthUsdFeed), "ETH_USD_FEED");
    vm.label(address(s_mockUsdcUsdFeed), "USDC_USD_FEED");
    vm.label(address(s_mockHdtUsdFeed), "HDT_USD_FEED");
  }

  function test_invariant() public {}
}
