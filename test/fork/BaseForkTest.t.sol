// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {FeeAggregator} from "src/FeeAggregator.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Roles} from "src/libraries/Roles.sol";
import {Mainnet} from "test/Addresses.t.sol";
import {BaseTest} from "test/BaseTest.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract BaseForkTest is BaseTest, Mainnet {
  uint256 private constant FORK_BLOCK = 20935485;

  FeeAggregator internal s_feeAggregatorReceiver;
  FeeAggregator internal s_feeAggregatorSender;
  SwapAutomator internal s_swapAutomator;
  SwapAutomator internal s_swapAutomatorSender;

  constructor() {
    vm.createSelectFork("mainnet", FORK_BLOCK);

    s_feeAggregatorReceiver = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: LINK,
        ccipRouterClient: CCIP_ROUTER,
        wrappedNativeToken: WETH
      })
    );

    s_feeAggregatorSender = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: LINK,
        ccipRouterClient: CCIP_ROUTER,
        wrappedNativeToken: WETH
      })
    );

    s_swapAutomator = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: LINK_USD_FEED,
        uniswapRouter: UNISWAP_ROUTER,
        uniswapQuoterV2: UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );

    s_swapAutomatorSender = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: LINK,
        feeAggregator: address(s_feeAggregatorSender),
        linkUsdFeed: LINK_USD_FEED,
        uniswapRouter: UNISWAP_ROUTER,
        uniswapQuoterV2: UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: i_receiver,
        maxPerformDataSize: MAX_PERFORM_DATA_SIZE
      })
    );

    s_feeAggregatorReceiver.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_feeAggregatorReceiver.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);
    s_feeAggregatorReceiver.grantRole(Roles.WITHDRAWER_ROLE, i_withdrawer);
    s_feeAggregatorReceiver.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomator));
    s_feeAggregatorSender.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_feeAggregatorSender.grantRole(Roles.UNPAUSER_ROLE, i_unpauser);
    s_feeAggregatorSender.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomatorSender));
    s_feeAggregatorSender.grantRole(Roles.WITHDRAWER_ROLE, i_withdrawer);
    s_swapAutomator.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);
    s_swapAutomator.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_swapAutomator.setForwarder(i_forwarder);
    s_feeAggregatorSender.grantRole(Roles.BRIDGER_ROLE, i_bridger);
    s_feeAggregatorSender.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);
    s_swapAutomatorSender.grantRole(Roles.ASSET_ADMIN_ROLE, i_assetAdmin);
    s_swapAutomatorSender.grantRole(Roles.PAUSER_ROLE, i_pauser);
    s_swapAutomatorSender.setForwarder(i_forwarder);

    address[] memory assets = new address[](6);
    assets[0] = WETH;
    assets[1] = USDC;
    assets[2] = USDT;
    assets[3] = DAI;
    // NOTE: Listing MATIC as an ABT causes CI to fail. After investigation this seems to be due to the MATIC token
    // migration to the POL token as the MATIC/WETH pool is being deprecated on ethereum. There is currently no POL/WETH
    // pool on uniswap v3 so I temporarily removed MATIC from the ABT list in the fork tests for now.
    // TODO: Re-add MATIC to the ABT list once a POL/WETH pool is available on uniswap v3
    // assets[4] = MATIC;
    assets[4] = WBTC;
    assets[5] = LINK;

    SwapAutomator.AssetSwapParamsArgs[] memory assetSwapParamsArgs = new SwapAutomator.AssetSwapParamsArgs[](6);
    assetSwapParamsArgs[0] = SwapAutomator.AssetSwapParamsArgs({
      asset: WETH,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(ETH_USD_FEED),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: bytes.concat(bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
      })
    });
    assetSwapParamsArgs[1] = SwapAutomator.AssetSwapParamsArgs({
      asset: USDC,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(USDC_USD_FEED),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: bytes.concat(bytes20(USDC), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
      })
    });
    assetSwapParamsArgs[2] = SwapAutomator.AssetSwapParamsArgs({
      asset: USDT,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(USDT_USD_FEED),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: bytes.concat(bytes20(USDT), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
      })
    });
    assetSwapParamsArgs[3] = SwapAutomator.AssetSwapParamsArgs({
      asset: DAI,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(DAI_USD_FEED),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: bytes.concat(bytes20(DAI), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
      })
    });
    // swapParams[4] = SwapAutomator.SwapParams({
    //   usdFeed: AggregatorV3Interface(MATIC_USD_FEED),
    //   maxSlippage: MAX_SLIPPAGE,
    //   minSwapSizeUsd: MIN_SWAP_SIZE,
    //   maxSwapSizeUsd: MAX_SWAP_SIZE,
    //   maxPriceDeviation: MAX_PRICE_DEVIATION,
    //   swapInterval: SWAP_INTERVAL,
    //   path: bytes.concat(bytes20(MATIC), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    // });
    assetSwapParamsArgs[4] = SwapAutomator.AssetSwapParamsArgs({
      asset: WBTC,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(WBTC_USD_FEED),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: bytes.concat(bytes20(WBTC), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
      })
    });
    assetSwapParamsArgs[5] = SwapAutomator.AssetSwapParamsArgs({
      asset: LINK,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(LINK_USD_FEED),
        maxSlippage: 1,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: type(uint128).max,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: bytes.concat(bytes20(LINK), bytes3(uint24(3000)), bytes20(LINK))
      })
    });

    _changePrank(i_assetAdmin);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), assets);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), assetSwapParamsArgs);
    s_swapAutomatorSender.applyAssetSwapParamsUpdates(new address[](0), assetSwapParamsArgs);
    _changePrank(i_owner);

    FeeAggregator.AllowlistedReceivers[] memory allowlistedReceivers = new FeeAggregator.AllowlistedReceivers[](1);

    bytes[] memory receiverAddresses = new bytes[](1);
    receiverAddresses[0] = abi.encodePacked(address(s_feeAggregatorReceiver));

    allowlistedReceivers[0] = FeeAggregator.AllowlistedReceivers({
      remoteChainSelector: DESTINATION_CHAIN_SELECTOR,
      receivers: receiverAddresses
    });

    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);

    s_feeAggregatorSender.applyAllowlistedReceiverUpdates(emptyReceivers, allowlistedReceivers);

    vm.label(address(s_feeAggregatorReceiver), "FeeAggregatorReceiver");
    vm.label(address(s_feeAggregatorSender), "FeeAggregatorSender");
    vm.label(address(s_swapAutomator), "SwapAutomator");
    vm.label(address(s_swapAutomatorSender), "SwapAutomatorSender");
    vm.label(i_owner, "Owner");
    vm.label(i_assetAdmin, "Asset Admin");
    vm.label(CCIP_ROUTER, "CCIP Router");
    vm.label(LINK, "LINK");
    vm.label(WETH, "WETH");
    vm.label(USDC, "USDC");
    vm.label(USDT, "USDT");
    vm.label(DAI, "DAI");
    // vm.label(MATIC, "MATIC");
    vm.label(WBTC, "WBTC");
    vm.label(LINK_USD_FEED, "LINK/USD Feed");
    vm.label(ETH_USD_FEED, "ETH/USD Feed");
    vm.label(USDC_USD_FEED, "USDC/USD Feed");
    vm.label(USDT_USD_FEED, "USDT/USD Feed");
    vm.label(DAI_USD_FEED, "DAI/USD Feed");
    vm.label(MATIC_USD_FEED, "MATIC/USD Feed");
    vm.label(WBTC_USD_FEED, "WBTC/USD Feed");
    vm.label(UNISWAP_ROUTER, "Uniswap Router");
  }

  function test_baseForkTest() public {}

  function _deal(address token, address to, uint256 amount) internal {
    if (token == USDC) {
      vm.store(USDC, keccak256(abi.encode(to, 9)), bytes32(amount));
    } else {
      deal(token, to, amount);
    }
  }

  function _dealSwapAmount(address asset, address to, uint256 swapValue) internal {
    uint256 assetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(asset).usdFeed);
    uint256 assetDecimals = IERC20Metadata(asset).decimals();
    uint256 amount = swapValue < assetPrice ? 10 ** assetDecimals : ((swapValue * 10 ** assetDecimals) / assetPrice);
    _deal(asset, to, amount);
  }
}
