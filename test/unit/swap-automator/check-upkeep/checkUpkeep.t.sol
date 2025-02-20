// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {FeeAggregator} from "src/FeeAggregator.sol";
import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";

contract CheckUpkeepUnitTest is BaseUnitTest {
  using stdStorage for StdStorage;

  address private constant AUTOMATION_SIMULATION_ADDRESS = address(0);
  int256 private constant ASSET_1_USD_PRICE = 1_000e8; // 1 000 USD
  int256 private constant ASSET_2_USD_PRICE = 1e8; // 1 USD
  int256 private constant ASSET_3_USD_PRICE = 1e18; // 1 USD
  int256 private constant ASSET_4_USD_PRICE = 1e3; // 1 USD
  int256 private constant LINK_USD_PRICE = 10e8;

  uint256 private constant DEFAULT_AMOUNT_IN_ASSET_1 = 100 ether;
  uint256 private constant DEFAULT_AMOUNT_IN_ASSET_2 = 100_000e6;
  uint256 private constant DEFAULT_AMOUNT_IN_ASSET_3 = 100_000 ether;
  uint256 private constant DEFAULT_AMOUNT_IN_ASSET_4 = 100_000 ether;
  uint256 private constant AMOUNT_OUT_FROM_FEED = 10_000e18; // Mock Raw amount out from feed
  // without slippage applied.
  uint256 private constant QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_PROCEED = 9_900e18;
  uint256 private constant QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_NOT_PROCEED = 9_000e18; // Lower
  // than amountOutFeedWithSlippage
  uint256 private constant QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT = 10_100e18;
  uint256 private constant EXPECTED_MIN_AMOUNT_OUT_FROM_FEED = 9_800e18; // Expected MinAmountOut
  // from feed with slippage applied.
  uint256 private constant EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER = 9_898e18; // Expected MinAmountOut from uniswap quoter
  // with slippage applied.
  bytes internal constant ASSET_3_SWAP_PATH = bytes("ASSET_3_SWAP_PATH");
  bytes internal constant ASSET_4_SWAP_PATH = bytes("ASSET_4_SWAP_PATH");

  // High decimals feed
  address private immutable i_asset3 = makeAddr("asset3");
  address private immutable i_asset3UsdFeed = makeAddr("asset3UsdFeed");
  // Low decimals feed
  address private immutable i_asset4 = makeAddr("asset4");
  address private immutable i_asset4UsdFeed = makeAddr("asset4UsdFeed");

  modifier whenPaused(
    address contractAddress
  ) {
    _changePrank(i_pauser);
    PausableWithAccessControl(contractAddress).emergencyPause();
    _;
  }

  modifier givenFeedDataIsZero(
    address usdFeed
  ) {
    (,,,, uint256 updatedAt) = AggregatorV3Interface(usdFeed).latestRoundData();
    vm.mockCall(
      usdFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 0, 0, updatedAt, 0)
    );
    _;
  }

  modifier givenFeedDataIsStale(
    address usdFeed
  ) {
    (, int256 answer,,,) = AggregatorV3Interface(usdFeed).latestRoundData();
    vm.mockCall(
      usdFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, answer, 0, 0, 0)
    );
    _;
  }

  function _givenAssetSufficientBalanceForSwap(
    address asset
  ) private {
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(asset);
    uint256 assetBalance =
      (swapParams.maxSwapSizeUsd * 10 ** IERC20Metadata(asset).decimals()) / _getAssetPrice(swapParams.usdFeed);

    vm.mockCall(
      asset,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)),
      abi.encode(assetBalance)
    );
  }

  modifier givenAssetSufficientBalanceForSwap(
    address asset
  ) {
    _givenAssetSufficientBalanceForSwap(asset);
    _;
  }

  /**
   * Modifer for mocking the UniswapRouterV2 quoteExactInput(), given assetSwapPath and amountIn,
   * return mockAmountOut.
   */
  modifier givenAssetUniswapQuoterAmountOut(
    bytes memory givenAssetSwapPath,
    uint256 givenAmountIn,
    uint256 mockAmountOut
  ) {
    vm.mockCall(
      i_mockUniswapQuoterV2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, givenAssetSwapPath, givenAmountIn),
      abi.encode(mockAmountOut, "", "", "")
    );
    _;
  }

  modifier givenAssetElapsedTimeSinceLastSwapLtSwapInterval(
    address asset
  ) {
    stdstore.target(address(s_swapAutomator)).sig("getLatestSwapTimestamp(address)").with_key(asset).checked_write(
      block.timestamp
    );
    _;
  }

  /**
   * Modifier for mocking the asset balance to exceed the maxSwapSizeUsd.
   */
  modifier givenAssetBalanceExceedingMaxSwapSize(
    address asset
  ) {
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(asset);
    uint256 assetBalance =
      (swapParams.maxSwapSizeUsd * 10 ** IERC20Metadata(asset).decimals()) / _getAssetPrice(swapParams.usdFeed);

    vm.mockCall(
      asset,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)),
      abi.encode(assetBalance)
    );
    _;
  }

  function setUp() public {
    address[] memory assets = new address[](4);
    SwapAutomator.AssetSwapParamsArgs[] memory assetSwapParamsArgs = new SwapAutomator.AssetSwapParamsArgs[](4);
    assets[0] = i_asset1;
    assetSwapParamsArgs[0] = SwapAutomator.AssetSwapParamsArgs({
      asset: i_asset1,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(i_asset1UsdFeed),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: ASSET_1_SWAP_PATH
      })
    });
    assets[1] = i_asset2;
    assetSwapParamsArgs[1] = SwapAutomator.AssetSwapParamsArgs({
      asset: i_asset2,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(i_asset2UsdFeed),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE,
        maxSwapSizeUsd: MAX_SWAP_SIZE,
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: ASSET_2_SWAP_PATH
      })
    });
    assets[2] = i_asset3;
    assetSwapParamsArgs[2] = SwapAutomator.AssetSwapParamsArgs({
      asset: i_asset3,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(i_asset3UsdFeed),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE * 10 ** 10, // Feed decimals = 18
        maxSwapSizeUsd: MAX_SWAP_SIZE * 10 ** 10, // Feed decimals = 18
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: ASSET_3_SWAP_PATH
      })
    });
    assets[3] = i_asset4;
    assetSwapParamsArgs[3] = SwapAutomator.AssetSwapParamsArgs({
      asset: i_asset4,
      swapParams: SwapAutomator.SwapParams({
        usdFeed: AggregatorV3Interface(i_asset4UsdFeed),
        maxSlippage: MAX_SLIPPAGE,
        minSwapSizeUsd: MIN_SWAP_SIZE / 10 ** 5, // Feed decimals = 3
        maxSwapSizeUsd: MAX_SWAP_SIZE / 10 ** 5, // Feed decimals = 3
        maxPriceDeviation: MAX_PRICE_DEVIATION,
        swapInterval: SWAP_INTERVAL,
        stalenessThreshold: STALENESS_THRESHOLD,
        path: ASSET_4_SWAP_PATH
      })
    });

    _changePrank(i_assetAdmin);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), assetSwapParamsArgs);

    // Mock asset1 decimals
    vm.mockCall(i_asset1, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    // Moch asset1UsdFeed decimals
    vm.mockCall(i_asset1UsdFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8));
    // Mock asset1/USD price
    vm.mockCall(
      i_asset1UsdFeed,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, ASSET_1_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    /**
     *  Mock asset1 default AmountOut from Uniswap Quoter.
     *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
     *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
     */
    vm.mockCall(
      i_mockUniswapQuoterV2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_1_SWAP_PATH, DEFAULT_AMOUNT_IN_ASSET_1),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Mock asset2/USD price
    vm.mockCall(
      i_asset2, abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)), abi.encode(999e6)
    );
    // Mock asset2 decimals to 6 decimals
    vm.mockCall(i_asset2, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(6));
    // Moch asset2UsdFeed decimals
    vm.mockCall(i_asset2UsdFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8));
    // Mock asset2/USD price
    vm.mockCall(
      i_asset2UsdFeed,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, ASSET_2_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    /**
     *  Mock asset2 default AmountOut from Uniswap Quoter.
     *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
     *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
     */
    vm.mockCall(
      i_mockUniswapQuoterV2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_2_SWAP_PATH, DEFAULT_AMOUNT_IN_ASSET_2),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Mock asset3 decimals
    vm.mockCall(i_asset3, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    // Moch asset3UsdFeed decimals
    vm.mockCall(i_asset3UsdFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(18));
    // Mock asset3/USD price
    vm.mockCall(
      i_asset3UsdFeed,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, ASSET_3_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    /**
     *  Mock asset3 default AmountOut from Uniswap Quoter.
     *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
     *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
     */
    vm.mockCall(
      i_mockUniswapQuoterV2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_3_SWAP_PATH, DEFAULT_AMOUNT_IN_ASSET_3),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Mock asset4 decimals
    vm.mockCall(i_asset4, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    // Moch asset4UsdFeed decimals
    vm.mockCall(i_asset4UsdFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(3));
    // Mock asset4/USD price
    vm.mockCall(
      i_asset4UsdFeed,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, ASSET_4_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    /**
     *  Mock asset3 default AmountOut from Uniswap Quoter.
     *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
     *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
     */
    vm.mockCall(
      i_mockUniswapQuoterV2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_4_SWAP_PATH, DEFAULT_AMOUNT_IN_ASSET_4),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Mock LINK/USD price
    vm.mockCall(
      i_mockLinkUSDFeed,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, LINK_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    // Set all initial asset balances to 0
    for (uint256 i; i < assets.length; ++i) {
      vm.mockCall(
        assets[i], abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)), abi.encode(0)
      );
    }
  }

  function test_checkUpkeep_RevertWhen_WhenContractIsPaused() public whenPaused(address(s_swapAutomator)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    _checkUpkeepWithSimulation();
  }

  function test_checkUpkeep_RevertWhen_LINKFeedDataIsZero()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
    givenFeedDataIsZero(i_mockLinkUSDFeed)
  {
    vm.expectRevert(Errors.ZeroFeedData.selector);
    _checkUpkeepWithSimulation();
  }

  function test_checkUpkeep_SkipAssetWhenSwapParamsAreNotSet()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
  {
    // add invalid asset to allowlist on the receiver
    address[] memory assets = new address[](1);
    assets[0] = i_invalidAsset;
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);

    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 2);
  }

  function test_checkUpkeep_SkipAsset1WhenAsset1FeedDataIsZero()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
    givenFeedDataIsZero(i_asset1UsdFeed)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_RevertWhen_LINKFeedDataIsStale()
    public
    givenFeedDataIsStale(i_mockLinkUSDFeed)
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
  {
    vm.expectRevert(Errors.StaleFeedData.selector);
    _checkUpkeepWithSimulation();
  }

  function test_checkUpkeep_SkipAssetOneWhenAsset1FeedDataIsStale()
    public
    givenFeedDataIsStale(i_asset1UsdFeed)
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_SkipAssetTwoWhenAsset2FeedDataIsStalee()
    public
    givenFeedDataIsStale(i_asset2UsdFeed)
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_NoEligibleAssets() public {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();

    assertFalse(upkeepNeeded);
    assertEq(performData.length, 0);
  }

  function test_checkUpkeep_OnlyEnoughAsset1Balance() public givenAssetSufficientBalanceForSwap(i_asset1) {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_OnlyEnoughAsset2Balance() public givenAssetSufficientBalanceForSwap(i_asset2) {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_OnlyAsset1AboveSwapInterval()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
    givenAssetElapsedTimeSinceLastSwapLtSwapInterval(i_asset2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));

    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_OnlyAsset2AboveInterval()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
    givenAssetElapsedTimeSinceLastSwapLtSwapInterval(i_asset1)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 2);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
    assertEq(keccak256(swapInputs[1].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[1].recipient, i_receiver);
    assertEq(swapInputs[1].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[1].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  /**
   * Test checkUpKeep filtering logic to still include trades that has
   *  amountOutPriceFeed > amountOutUniswapQuoter > amountOutPriceFeedWithSlippage.
   * Expected: UpKeep return true, minAmountOut = amountOutPriceFeed * (1 - Slippage)
   *
   */
  function test_checkUpkeep_Asset1QuoterAmountLowerThanFeedAmountButAboveMinimum()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
    givenAssetUniswapQuoterAmountOut(
      ASSET_1_SWAP_PATH,
      DEFAULT_AMOUNT_IN_ASSET_1,
      QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_PROCEED
    )
    givenAssetUniswapQuoterAmountOut(
      ASSET_2_SWAP_PATH,
      DEFAULT_AMOUNT_IN_ASSET_2,
      QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_PROCEED
    )
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 2);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_FEED);
    assertEq(keccak256(swapInputs[1].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[1].recipient, i_receiver);
    assertEq(swapInputs[1].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[1].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_FEED);
  }

  /**
   * Test checkUpKeep filtering logic to exclude trades that has
   * amountOutPriceFeed > amountOutPriceFeedWithSlippag > amountOutUniswapQuoter.
   * Expected: UpKeep returns false
   */
  function test_checkUpkeep_Asset1QuoterAmountLowerThanFeedAmountAndBelowMinimum()
    public
    givenAssetSufficientBalanceForSwap(i_asset1)
    givenAssetSufficientBalanceForSwap(i_asset2)
    givenAssetUniswapQuoterAmountOut(
      ASSET_1_SWAP_PATH,
      DEFAULT_AMOUNT_IN_ASSET_1,
      QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_NOT_PROCEED
    )
    givenAssetUniswapQuoterAmountOut(
      ASSET_2_SWAP_PATH,
      DEFAULT_AMOUNT_IN_ASSET_2,
      QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_NOT_PROCEED
    )
  {
    (bool upkeepNeeded,) = _checkUpkeepWithSimulation();
    assertFalse(upkeepNeeded);
  }

  /**
   * Test checkUpkeep when asset's USD value exceeds the maxSwapSizeUsd.
   * Expected: swapAmountIn should be limited to maxSwapSizeUsd converted to asset amount.
   */
  function test_checkUpkeep_WhenAssetUsdValueExceedsMaxSwapSize()
    public
    givenAssetBalanceExceedingMaxSwapSize(i_asset1)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    assertTrue(upkeepNeeded);

    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertEq(swapInputs.length, 1);

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(i_asset1);
    uint256 assetUnit = 10 ** IERC20Metadata(i_asset1).decimals();
    uint256 assetPrice = uint256(ASSET_1_USD_PRICE);

    uint256 expectedAmountIn = (swapParams.maxSwapSizeUsd * assetUnit) / assetPrice;

    assertEq(swapInputs[0].amountIn, expectedAmountIn);
  }

  function testFuzz_checkUpkeep_DifferingDecimals(int8 tokenDecimalOffset, int8 feedDecimalOffset) public {
    tokenDecimalOffset = int8(bound(tokenDecimalOffset, -6, 6));
    feedDecimalOffset = int8(bound(feedDecimalOffset, -6, 6));

    uint8 tokenDecimals = uint8(18 + tokenDecimalOffset);
    uint8 feedDecimals = uint8(8 + feedDecimalOffset);

    // Re-adjust token decimals & feed decimals from offset
    vm.mockCall(i_asset1, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(tokenDecimals));
    vm.mockCall(
      i_asset1UsdFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(feedDecimals)
    );

    // Re-adjust USD price from offset
    int256 adjustedUsdPrice = int256(_adjustValueToDecimals(uint256(ASSET_1_USD_PRICE), feedDecimalOffset));
    vm.mockCall(
      i_asset1UsdFeed,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, adjustedUsdPrice, block.timestamp, block.timestamp, 0)
    );

    // Re-adjust amountIn from offset
    uint256 adjustedAmountIn = _adjustValueToDecimals(DEFAULT_AMOUNT_IN_ASSET_1, tokenDecimalOffset);
    vm.mockCall(
      i_mockUniswapQuoterV2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_1_SWAP_PATH, adjustedAmountIn),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Re-adjust min / max sawp sizes from offset
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(i_asset1);
    swapParams.maxSwapSizeUsd = uint96(_adjustValueToDecimals(swapParams.maxSwapSizeUsd, feedDecimalOffset));
    swapParams.minSwapSizeUsd = uint96(_adjustValueToDecimals(swapParams.minSwapSizeUsd, feedDecimalOffset));

    SwapAutomator.AssetSwapParamsArgs[] memory assetSwapParamsArgs = new SwapAutomator.AssetSwapParamsArgs[](1);
    assetSwapParamsArgs[0] = SwapAutomator.AssetSwapParamsArgs({asset: i_asset1, swapParams: swapParams});
    _changePrank(i_assetAdmin);
    s_swapAutomator.applyAssetSwapParamsUpdates(new address[](0), assetSwapParamsArgs);

    _givenAssetSufficientBalanceForSwap(i_asset1);

    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, i_receiver);
    assertEq(swapInputs[0].amountIn, adjustedAmountIn);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  /**
   * Test checkUpkeep when the performData exceeds the maximum size.
   * Expected: The performData should always be lower than the set threshold, the checkUpkeep function is expected to
   * stop populating the array of assets to swap if it reaches the maximum size.
   */
  function test_checkUpkeep_PerformDataSizeLtMaxPerformDataSize() public {
    address[] memory assets = new address[](7);
    SwapAutomator.AssetSwapParamsArgs[] memory assetSwapParamsArgs = new SwapAutomator.AssetSwapParamsArgs[](7);

    // For simplicity we remove the already configured assets and replace them with standardized ones
    for (uint256 i; i < assets.length; ++i) {
      address asset = address(bytes20(keccak256(abi.encode("asset", i))));
      address assetUsdFeed = address(bytes20(keccak256(abi.encode("asset", 10 + i))));
      bytes memory path =
        bytes.concat(bytes20(asset), bytes3(uint24(3000)), bytes20(i_asset2), bytes3(uint24(3000)), bytes20(i_mockLink));
      assets[i] = asset;
      assetSwapParamsArgs[i] = SwapAutomator.AssetSwapParamsArgs({
        asset: asset,
        swapParams: SwapAutomator.SwapParams({
          usdFeed: AggregatorV3Interface(assetUsdFeed),
          maxSlippage: MAX_SLIPPAGE,
          minSwapSizeUsd: MIN_SWAP_SIZE,
          maxSwapSizeUsd: MAX_SWAP_SIZE,
          maxPriceDeviation: MAX_PRICE_DEVIATION,
          swapInterval: SWAP_INTERVAL,
          stalenessThreshold: STALENESS_THRESHOLD,
          path: path
        })
      });

      // Mock asset decimals
      vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
      // Moch assetUsdFeed decimals
      vm.mockCall(assetUsdFeed, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8));
      // Mock asset/USD price
      vm.mockCall(
        assetUsdFeed,
        abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
        abi.encode(0, 1_000e8, block.timestamp, block.timestamp, 0)
      );
      /**
       *  Mock asset default AmountOut from Uniswap Quoter.
       *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
       *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
       */
      vm.mockCall(
        i_mockUniswapQuoterV2,
        abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, path, 100 ether),
        abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
      );
      // Mock FeeAggregator asset balance
      vm.mockCall(
        asset,
        abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)),
        abi.encode(100 ether)
      );
    }

    // Reset allowlist
    _changePrank(i_assetAdmin);
    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(allowlistedAssets, assets);
    s_swapAutomator.applyAssetSwapParamsUpdates(allowlistedAssets, assetSwapParamsArgs);

    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    (IV3SwapRouter.ExactInputParams[] memory swapInputs,) =
      abi.decode(performData, (IV3SwapRouter.ExactInputParams[], uint256));

    // performData is composed of:
    // Fixed:
    // 0x0000000000000000000000000000000000000000000000000000000000000040 -> data offset
    // 0x0000000000000000000000000000000000000000000000000000000000093abd -> deadline
    // 0x0000000000000000000000000000000000000000000000000000000000000001 -> exactInputParams length
    // Per asset:
    // 0x0000000000000000000000000000000000000000000000000000000000000020 -> offset to struct
    // 0x0000000000000000000000000000000000000000000000000000000000000080 -> offset to path
    // 0x000000000000000000000000b6d4805bf6943c5875c0c7b67eda24b2bdacbf6e -> receiver
    // 0x0000000000000000000000000000000000000000000000056bc75e2d63100000 -> amountIn
    // 0x0000000000000000000000000000000000000000000002189257fe2600680000 -> amountOutMinimum
    // 0x0000000000000000000000000000000000000000000000000000000000000042 -> path length
    // 0x81ee54617d9040b6201bc99ff05f2820d8423a15000bb87113c56b9bf5c08b36 -> path
    // 0x02d7da8344aaf79239eae0000bb8a9efe8412aec2cf9f090c277ef77a12cfc7c -> path
    // 0x7b79000000000000000000000000000000000000000000000000000000000000 -> path

    // To reach a performData size of 2000, we need:
    // 32 * 3 + 9 * 32x = 2000 where x is the number of assets
    // x = 6.61
    // 7 assets to swap will exceed the maximum performData size of 2000 so the checkUpkeep should only return 6 assets
    // to swap

    assertTrue(upkeepNeeded);
    assertEq(performData.length, 3 * 32 + 9 * 32 * 6); // 1,824 bytes
    assertEq(swapInputs.length, 6);
  }

  function _checkUpkeepWithSimulation() internal returns (bool, bytes memory) {
    // Changing the msg.sender and tx.origin to simulation add since checkUpKeep() is cannotExecute
    _changePrank(AUTOMATION_SIMULATION_ADDRESS, AUTOMATION_SIMULATION_ADDRESS);
    return s_swapAutomator.checkUpkeep("");
  }

  function _adjustValueToDecimals(uint256 value, int8 decimalOffset) internal pure returns (uint256) {
    if (decimalOffset > 0) {
      return value * (10 ** (uint8(decimalOffset)));
    } else {
      return value / (10 ** (uint8(-1 * decimalOffset)));
    }
  }
}
