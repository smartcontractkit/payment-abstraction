// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
  int256 private constant ASSET_1_USD_PRICE = 1_000e8;
  int256 private constant ASSET_2_USD_PRICE = 1e8;
  int256 private constant LINK_USD_PRICE = 10e8;

  uint256 private constant DEFAULT_AMOUNT_IN_ASSET_1 = 100 ether;
  uint256 private constant DEFAULT_AMOUNT_IN_ASSET_2 = 100_000e6;
  uint256 private constant AMOUNT_OUT_FROM_ORCALE = 10_000e18; // Mock Raw amount out from oracle
  // without slippage applied.
  uint256 private constant QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_PROCEED = 9_900e18;
  uint256 private constant QUOTER_AMOUNT_LOWER_THAN_FEED_AMOUNT_SHOULD_NOT_PROCEED = 9_000e18; // Lower
  // than amountOutOracleWithSlippage
  uint256 private constant QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT = 10_100e18;
  uint256 private constant EXPECTED_MIN_AMOUNT_OUT_FROM_ORACLE = 9_800e18; // Expected MinAmountOut
  // from oracle with slippage applied.
  uint256 private constant EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER = 9_898e18; // Expected MinAmountOut
  // from uniswap quoter with
  // slippage applied.

  modifier whenPaused(
    address contractAddress
  ) {
    _changePrank(PAUSER);
    PausableWithAccessControl(contractAddress).emergencyPause();
    _;
  }

  modifier givenOracleDataIsZero(
    address oracle
  ) {
    (,,,, uint256 updatedAt) = AggregatorV3Interface(oracle).latestRoundData();
    vm.mockCall(
      oracle, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 0, 0, updatedAt, 0)
    );
    _;
  }

  modifier givenOracleDataIsStale(
    address oracle
  ) {
    (, int256 answer,,,) = AggregatorV3Interface(oracle).latestRoundData();
    vm.mockCall(
      oracle, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, answer, 0, 0, 0)
    );
    _;
  }

  modifier givenAssetSufficientBalanceForSwap(
    address asset
  ) {
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(asset);
    uint256 assetBalance =
      (swapParams.maxSwapSizeUsd * 10 ** IERC20Metadata(asset).decimals()) / _getAssetPrice(swapParams.oracle);

    vm.mockCall(
      asset,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)),
      abi.encode(assetBalance)
    );
    _;
  }

  modifier givenAssetInsufficientBalanceForSwap(
    address asset
  ) {
    vm.mockCall(
      asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)), abi.encode(0)
    );
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
      MOCK_UNISWAP_QUOTER_V2,
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
      (swapParams.maxSwapSizeUsd * 10 ** IERC20Metadata(asset).decimals()) / _getAssetPrice(swapParams.oracle);

    vm.mockCall(
      asset,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)),
      abi.encode(assetBalance)
    );
    _;
  }

  function setUp() public {
    address[] memory assets = new address[](2);
    SwapAutomator.SwapParams[] memory swapParams = new SwapAutomator.SwapParams[](2);
    assets[0] = ASSET_1;
    swapParams[0] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ASSET_1_ORACLE),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: ASSET_1_SWAP_PATH
    });
    assets[1] = ASSET_2;
    swapParams[1] = SwapAutomator.SwapParams({
      oracle: AggregatorV3Interface(ASSET_2_ORACLE),
      maxSlippage: MAX_SLIPPAGE,
      minSwapSizeUsd: MIN_SWAP_SIZE,
      maxSwapSizeUsd: MAX_SWAP_SIZE,
      maxPriceDeviation: MAX_PRICE_DEVIATION,
      swapInterval: SWAP_INTERVAL,
      path: ASSET_2_SWAP_PATH
    });

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);
    s_swapAutomator.applyAssetSwapParamsUpdates(
      new address[](0), SwapAutomator.AssetSwapParamsArgs({assets: assets, assetsSwapParams: swapParams})
    );

    // Mock ASSET_1 decimals
    vm.mockCall(ASSET_1, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    // Moch ASSET_1_ORACLE decimals
    vm.mockCall(ASSET_1_ORACLE, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8));
    // Mock ASSET_1/USD price
    vm.mockCall(
      ASSET_1_ORACLE,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, ASSET_1_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    /**
     *  Mock ASSET_1 default AmountOut from Uniswap Quoter.
     *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
     *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
     */
    vm.mockCall(
      MOCK_UNISWAP_QUOTER_V2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_1_SWAP_PATH, DEFAULT_AMOUNT_IN_ASSET_1),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Mock ASSET_2/USD price
    vm.mockCall(
      ASSET_2, abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_feeAggregatorReceiver)), abi.encode(999e6)
    );
    // Mock ASSET_2 decimals to 6 decimals
    vm.mockCall(ASSET_2, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(6));
    // Moch ASSET_2_ORACLE decimals
    vm.mockCall(ASSET_2_ORACLE, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(8));
    // Mock ASSET_2/USD price
    vm.mockCall(
      ASSET_2_ORACLE,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, ASSET_2_USD_PRICE, block.timestamp, block.timestamp, 0)
    );

    /**
     * Mock ASSET_2 default AmountOut from Uniswap Quoter.
     *  In default(unless test overriden with givenAssetUniswapQuoterAmountOut()),
     *  amountOutUniswapQuoter > amountOutPriceFeed > amountOutPriceFeedWithSlippage
     */
    vm.mockCall(
      MOCK_UNISWAP_QUOTER_V2,
      abi.encodeWithSelector(IQuoterV2.quoteExactInput.selector, ASSET_2_SWAP_PATH, DEFAULT_AMOUNT_IN_ASSET_2),
      abi.encode(QUOTER_AMOUNT_HIGHER_THAN_FEED_AMOUNT, "", "", "")
    );

    // Mock LINK/USD price
    vm.mockCall(
      MOCK_LINK_USD_FEED,
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, LINK_USD_PRICE, block.timestamp, block.timestamp, 0)
    );
  }

  function test_checkUpkeep_RevertWhen_WhenContractIsPaused() public whenPaused(address(s_swapAutomator)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    _checkUpkeepWithSimulation();
  }

  function test_checkUpkeep_RevertWhen_LINKOracleDataIsZero()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
    givenOracleDataIsZero(MOCK_LINK_USD_FEED)
  {
    vm.expectRevert(Errors.ZeroOracleData.selector);
    _checkUpkeepWithSimulation();
  }

  function test_checkUpkeep_SkipAssetWhenSwapParamsAreNotSet()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
  {
    // add invalid asset to allowlist on the receiver
    address[] memory assets = new address[](1);
    assets[0] = INVALID_ASSET;
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), assets);

    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 2);
  }

  function test_checkUpkeep_SkipAsset1WhenAsset1OracleDataIsZero()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
    givenOracleDataIsZero(ASSET_1_ORACLE)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_RevertWhen_LINKOracleDataIsStale()
    public
    givenOracleDataIsStale(MOCK_LINK_USD_FEED)
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
  {
    vm.expectRevert(Errors.StaleOracleData.selector);
    _checkUpkeepWithSimulation();
  }

  function test_checkUpkeep_SkipAssetOneWhenAsset1OracleDataIsStale()
    public
    givenOracleDataIsStale(ASSET_1_ORACLE)
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_SkipAssetTwoWhenAsset2OracleDataIsStalee()
    public
    givenOracleDataIsStale(ASSET_2_ORACLE)
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));
    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_NoEligibleAssets()
    public
    givenAssetInsufficientBalanceForSwap(ASSET_1)
    givenAssetInsufficientBalanceForSwap(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();

    assertFalse(upkeepNeeded);
    assertEq(performData.length, 0);
  }

  function test_checkUpkeep_OnlyEnoughAsset1Balance()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetInsufficientBalanceForSwap(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_OnlyEnoughAsset2Balance()
    public
    givenAssetSufficientBalanceForSwap(ASSET_2)
    givenAssetInsufficientBalanceForSwap(ASSET_1)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_OnlyAsset1AboveSwapInterval()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
    givenAssetElapsedTimeSinceLastSwapLtSwapInterval(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));

    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep_OnlyAsset2AboveInterval()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
    givenAssetElapsedTimeSinceLastSwapLtSwapInterval(ASSET_1)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 1);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  function test_checkUpkeep()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertTrue(upkeepNeeded);
    assertEq(swapInputs.length, 2);
    assertEq(keccak256(swapInputs[0].path), keccak256(ASSET_1_SWAP_PATH));
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
    assertEq(keccak256(swapInputs[1].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[1].recipient, RECEIVER);
    assertEq(swapInputs[1].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[1].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_QUOTER);
  }

  /**
   * Test checkUpKeep filtering logic to still include trades that has
   *  amountOutPriceFeed > amountOutUniswapQuoter > amountOutPriceFeedWithSlippage.
   * Expected: UpKeep return true, minAmountOut = amountOutPriceFeed * (1 - Slippage)
   *
   */
  function test_checkUpkeep_Asset1QuoterAmountLowerThanOracleAmountButAboveMinimum()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
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
    assertEq(swapInputs[0].recipient, RECEIVER);
    assertEq(swapInputs[0].amountIn, DEFAULT_AMOUNT_IN_ASSET_1);
    assertEq(swapInputs[0].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_ORACLE);
    assertEq(keccak256(swapInputs[1].path), keccak256(ASSET_2_SWAP_PATH));
    assertEq(swapInputs[1].recipient, RECEIVER);
    assertEq(swapInputs[1].amountIn, DEFAULT_AMOUNT_IN_ASSET_2);
    assertEq(swapInputs[1].amountOutMinimum, EXPECTED_MIN_AMOUNT_OUT_FROM_ORACLE);
  }

  /**
   * Test checkUpKeep filtering logic to exclude trades that has
   * amountOutPriceFeed > amountOutPriceFeedWithSlippag > amountOutUniswapQuoter.
   * Expected: UpKeep returns false
   */
  function test_checkUpkeep_Asset1QuoterAmountLowerThanOracleAmountAndBelowMinimum()
    public
    givenAssetSufficientBalanceForSwap(ASSET_1)
    givenAssetSufficientBalanceForSwap(ASSET_2)
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
    givenAssetBalanceExceedingMaxSwapSize(ASSET_1)
    givenAssetInsufficientBalanceForSwap(ASSET_2)
  {
    (bool upkeepNeeded, bytes memory performData) = _checkUpkeepWithSimulation();
    assertTrue(upkeepNeeded);

    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(performData, (IV3SwapRouter.ExactInputParams[]));

    assertEq(swapInputs.length, 1);

    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(ASSET_1);
    uint256 assetUnit = 10 ** IERC20Metadata(ASSET_1).decimals();
    uint256 assetPrice = uint256(ASSET_1_USD_PRICE);

    uint256 expectedAmountIn = (swapParams.maxSwapSizeUsd * assetUnit) / assetPrice;

    assertEq(swapInputs[0].amountIn, expectedAmountIn);
  }

  function _checkUpkeepWithSimulation() internal returns (bool, bytes memory) {
    // Changing the msg.sender and tx.origin to simulation add since checkUpKeep() is cannotExecute
    _changePrank(AUTOMATION_SIMULATION_ADDRESS, AUTOMATION_SIMULATION_ADDRESS);
    return s_swapAutomator.checkUpkeep("");
  }
}
