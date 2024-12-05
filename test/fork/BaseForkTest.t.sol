// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: LINK,
        ccipRouterClient: CCIP_ROUTER,
        wrappedNativeToken: WETH
      })
    );

    s_feeAggregatorSender = new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: LINK,
        ccipRouterClient: CCIP_ROUTER,
        wrappedNativeToken: WETH
      })
    );

    s_swapAutomator = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: LINK,
        feeAggregator: address(s_feeAggregatorReceiver),
        linkUsdFeed: LINK_USD_FEED,
        uniswapRouter: UNISWAP_ROUTER,
        uniswapQuoterV2: UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );

    s_swapAutomatorSender = new SwapAutomator(
      SwapAutomator.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: LINK,
        feeAggregator: address(s_feeAggregatorSender),
        linkUsdFeed: LINK_USD_FEED,
        uniswapRouter: UNISWAP_ROUTER,
        uniswapQuoterV2: UNISWAP_QUOTER_V2,
        deadlineDelay: DEADLINE_DELAY,
        linkReceiver: RECEIVER
      })
    );

    s_feeAggregatorReceiver.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeAggregatorReceiver.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);
    s_feeAggregatorReceiver.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_feeAggregatorReceiver.grantRole(Roles.WITHDRAWER_ROLE, WITHDRAWER);
    s_feeAggregatorReceiver.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomator));
    s_feeAggregatorSender.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_feeAggregatorSender.grantRole(Roles.UNPAUSER_ROLE, UNPAUSER);
    s_feeAggregatorSender.grantRole(Roles.SWAPPER_ROLE, address(s_swapAutomatorSender));
    s_feeAggregatorSender.grantRole(Roles.WITHDRAWER_ROLE, WITHDRAWER);
    s_swapAutomator.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_swapAutomator.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_swapAutomator.setForwarder(FORWARDER);
    s_feeAggregatorSender.grantRole(Roles.BRIDGER_ROLE, BRIDGER);
    s_feeAggregatorSender.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_swapAutomatorSender.grantRole(Roles.ASSET_ADMIN_ROLE, ASSET_ADMIN);
    s_swapAutomatorSender.grantRole(Roles.PAUSER_ROLE, PAUSER);
    s_swapAutomatorSender.setForwarder(FORWARDER);

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

    SwapAutomator.SwapParams[] memory swapParams = new SwapAutomator.SwapParams[](6);
    swapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ETH_USD_FEED),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: bytes.concat(bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    });
    swapParams[1] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(USDC_USD_FEED),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: bytes.concat(bytes20(USDC), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    });
    swapParams[2] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(USDT_USD_FEED),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: bytes.concat(bytes20(USDT), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    });
    swapParams[3] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(DAI_USD_FEED),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: bytes.concat(bytes20(DAI), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    });
    // swapParams[4] = SwapAutomator.SwapParams({
    //   oracle: AggregatorV3Interface(MATIC_USD_FEED),
    //   maxSlippage: MAX_SLIPPAGE,
    //   minSwapSizeUsd: MIN_SWAP_SIZE,
    //   maxSwapSizeUsd: MAX_SWAP_SIZE,
    //   maxPriceDeviation: MAX_PRICE_DEVIATION,
    //   swapInterval: SWAP_INTERVAL,
    //   path: bytes.concat(bytes20(MATIC), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    // });
    swapParams[4] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(WBTC_USD_FEED),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: bytes.concat(bytes20(WBTC), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK))
    });
    swapParams[5] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(LINK_USD_FEED),
      maxSlippage: 1,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: type(uint128).max,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: bytes.concat(bytes20(LINK), bytes3(uint24(3000)), bytes20(LINK))
    });

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorSender.applyAllowlistedAssetUpdates(new address[](0), assets);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: assets, assetsSwapParams: swapParams})
    );
    s_swapAutomatorSender.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: assets, assetsSwapParams: swapParams})
    );
    _changePrank(OWNER);

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
    vm.label(OWNER, "OWNER");
    vm.label(ASSET_ADMIN, "ASSET_ADMIN");
    vm.label(CCIP_ROUTER, "CCIP_ROUTER_CLIENT");
    vm.label(LINK, "LINK");
    vm.label(WETH, "WETH");
    vm.label(USDC, "USDC");
    vm.label(USDT, "USDT");
    vm.label(DAI, "DAI");
    // vm.label(MATIC, "MATIC");
    vm.label(WBTC, "WBTC");
    vm.label(LINK_USD_FEED, "MOCK_LINK_USD_FEED");
    vm.label(ETH_USD_FEED, "ETH_USD_FEED");
    vm.label(USDC_USD_FEED, "USDC_USD_FEED");
    vm.label(USDT_USD_FEED, "USDT_USD_FEED");
    vm.label(DAI_USD_FEED, "DAI_USD_FEED");
    vm.label(MATIC_USD_FEED, "MATIC_USD_FEED");
    vm.label(WBTC_USD_FEED, "WBTC_USD_FEED");
    vm.label(UNISWAP_ROUTER, "UNISWAP_ROUTER");
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
    uint256 assetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(asset).oracle);
    uint256 assetDecimals = IERC20Metadata(asset).decimals();
    uint256 amount = swapValue < assetPrice ? 10 ** assetDecimals : ((swapValue * 10 ** assetDecimals) / assetPrice);
    _deal(asset, to, amount);
  }
}
