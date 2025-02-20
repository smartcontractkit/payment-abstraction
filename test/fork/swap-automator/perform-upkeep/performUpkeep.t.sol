// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapAutomator} from "src/SwapAutomator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseForkTest} from "test/fork/BaseForkTest.t.sol";

import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

contract PerformUpkeepForkTest is BaseForkTest {
  using PercentageMath for uint256;

  address private constant AUTOMATION_SIMULATION_ADDRESS = address(0);

  modifier whenCallerIsNotForwarder() {
    _changePrank(address(this));
    _;
  }

  modifier givenAssetEligibleForSwap(
    address asset
  ) {
    _dealSwapAmount(asset, address(s_feeAggregatorReceiver), MAX_SWAP_SIZE);
    _;
  }

  function setUp() public {
    _changePrank(i_forwarder);
  }

  function test_performUpkeep_RevertWhen_ContractIsPaused() public givenContractIsPaused(address(s_swapAutomator)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_swapAutomator.performUpkeep("");
  }

  function test_performUpkeep_RevertWhen_CallerIsNotForwarder() public whenCallerIsNotForwarder {
    vm.expectRevert(Errors.AccessForbidden.selector);
    s_swapAutomator.performUpkeep("");
  }

  function test_performUpkeep_RevertWhen_TxTimestampGtDeadline() public givenAssetEligibleForSwap(WETH) {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    skip(DEADLINE_DELAY + 1);
    vm.expectRevert(
      abi.encodeWithSelector(SwapAutomator.TransactionTooOld.selector, block.timestamp, block.timestamp - 1)
    );
    s_swapAutomator.performUpkeep(data);
  }

  function test_performUpkeep_RevertWhen_AllSwapsFail()
    public
    givenAssetEligibleForSwap(WETH)
    givenAssetEligibleForSwap(USDC)
  {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    // Mock Uniswap logic
    vm.mockCallRevert(
      UNISWAP_ROUTER, abi.encodeWithSelector(IV3SwapRouter.exactInput.selector), abi.encode("Too little received")
    );

    (IV3SwapRouter.ExactInputParams[] memory swapInputs,) =
      abi.decode(data, (IV3SwapRouter.ExactInputParams[], uint256));

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapFailure(WETH, swapInputs[0]);

    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapFailure(USDC, swapInputs[1]);

    vm.expectRevert(SwapAutomator.AllSwapsFailed.selector);
    s_swapAutomator.performUpkeep(data);
  }

  function test_performUpkeep_WhenTryingToSwapLINK() public givenAssetEligibleForSwap(LINK) {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    uint256 amountInLINK = IERC20(LINK).balanceOf(address(s_feeAggregatorReceiver));

    uint256 feeReceiverBalanceBefore = IERC20(LINK).balanceOf(i_receiver);
    s_swapAutomator.performUpkeep(data);
    assertEq(IERC20(LINK).balanceOf(i_receiver), feeReceiverBalanceBefore + amountInLINK);
  }

  function test_performUpkeep_swapWithPriceFeedValidation_RevertWhen_NotSelfCalled()
    public
    givenAssetEligibleForSwap(WETH)
  {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    (IV3SwapRouter.ExactInputParams[] memory swapInputs,) =
      abi.decode(data, (IV3SwapRouter.ExactInputParams[], uint256));

    vm.expectRevert(Errors.AccessForbidden.selector);
    s_swapAutomator.swapWithPriceFeedValidation(swapInputs[0], address(0), 0);
  }

  /**
   * Revert when the forwarder is corrupted and forward any recipent address that's different to
   * FeeAggregator's recipient address.
   */
  function test_performUpkeep_RevertWhen_RecipentMismatch()
    public
    givenAssetEligibleForSwap(WETH)
    givenAssetEligibleForSwap(USDC)
  {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    // Intercept and corrupt the recipent of one asset's performData
    (IV3SwapRouter.ExactInputParams[] memory swapInputs, uint256 deadline) =
      abi.decode(data, (IV3SwapRouter.ExactInputParams[], uint256));
    swapInputs[0].recipient = address(0);
    data = abi.encode(swapInputs, deadline);
    vm.expectRevert(abi.encodeWithSelector(SwapAutomator.FeeRecipientMismatch.selector, swapInputs[0].recipient));
    s_swapAutomator.performUpkeep(data);
  }

  /**
   * Revert when the forwarder is corrupted and forward any swap path that does not match the
   * pregistered swap path in applyAssetSwapParamsUpdates().
   */
  function test_performUpkeep_RevertWhen_SingleAssetSwapPathChangedToEmpty() public givenAssetEligibleForSwap(WETH) {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    // Intercept and corrupt the swap path of one asset's performData
    (IV3SwapRouter.ExactInputParams[] memory swapInputs, uint256 deadline) =
      abi.decode(data, (IV3SwapRouter.ExactInputParams[], uint256));
    bytes memory unmatchedPath =
      bytes.concat(bytes20(WETH), bytes3(uint24(3000)), bytes20(WETH), bytes3(uint24(3000)), bytes20(LINK));
    swapInputs[0].path = unmatchedPath;
    data = abi.encode(swapInputs, deadline);

    vm.expectRevert(SwapAutomator.InvalidSwapPath.selector);
    s_swapAutomator.performUpkeep(data);
  }

  function test_performUpkeep_RevertWhen_LINKTransfersFail()
    public
    givenAssetEligibleForSwap(WETH)
    givenAssetEligibleForSwap(LINK)
  {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    uint256 amountInLink = IERC20(LINK).balanceOf(address(s_feeAggregatorReceiver));

    vm.mockCall(
      LINK, abi.encodeWithSelector(LinkTokenInterface.transfer.selector, i_receiver, amountInLink), abi.encode(false)
    );

    vm.expectRevert();
    s_swapAutomator.performUpkeep(data);
  }

  function test_performUpkeep_PartialExactInputFailure()
    public
    givenAssetEligibleForSwap(WETH)
    givenAssetEligibleForSwap(USDC)
  {
    (, bytes memory data) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(data, (IV3SwapRouter.ExactInputParams[]));

    uint256 amountInWeth = IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver));
    uint256 amountInUsdc = IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver));
    uint256 swapValue = _getAssetPrice(s_swapAutomator.getAssetSwapParams(WETH).usdFeed) * amountInWeth;

    // Mock Uniswap logic
    vm.mockCallRevert(
      UNISWAP_ROUTER,
      abi.encodeWithSelector(IV3SwapRouter.exactInput.selector, swapInputs[1]),
      abi.encode("Too little received")
    );
    // Ignore topic 3 as the value will only be know post swap
    vm.expectEmit(true, true, false, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, WETH, amountInWeth, 0);
    vm.expectEmit(address(s_swapAutomator));
    emit SwapAutomator.AssetSwapFailure(USDC, swapInputs[1]);
    s_swapAutomator.performUpkeep(data);

    uint256 linkBalanceValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED)) * IERC20(LINK).balanceOf(i_receiver);
    uint256 minValue = swapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);

    assert(linkBalanceValue >= minValue);
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver)), amountInUsdc);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(WETH), block.timestamp);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(USDC), 0);
    assertEq(IERC20(USDC).allowance(address(s_swapAutomator), UNISWAP_ROUTER), 0);
  }

  /**
   * When amountOut from uniswapRouter is below deviation threshold, performUpkeep() should soft
   * revert for ABT.
   * Given:
   *  amountOut for WETH is below deviation threshold.
   * Expected:
   *  InsufficientAmountReceived() error should be swallowed and the swap and transfer of WETH
   * should be reverted.
   */
  function test_performUpkeep_SingleSwapSinglePool_StaleFeedPrice() public givenAssetEligibleForSwap(WETH) {
    // GIVEN
    (, bytes memory data) = _checkUpkeepWithSimulation();
    AggregatorV3Interface wethFeed = s_swapAutomator.getAssetSwapParams(WETH).usdFeed;
    uint256 amountIn = IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver));
    uint256 abtAssetPrice = _getAssetPrice(wethFeed);

    vm.mockCall(
      address(wethFeed),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      // Timestamp of 1 is below staleness threshold
      abi.encode(1, abtAssetPrice, 1, 1, abtAssetPrice)
    );

    /**
     * EXPECTED:
     * 1. StaleFeedData() error should be swallowed and the ETH swap and transfer
     * should be reverted.
     * 2. Since AllSwaps within performUpkeep only contain one failing swap, AllSwapsFailed() error
     * should be thrown.
     */
    vm.expectRevert(SwapAutomator.AllSwapsFailed.selector);
    s_swapAutomator.performUpkeep(data);

    // ABT should be transfer back to receiver contract and the allowance should be
    // reverted/decreased.
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), amountIn);
    assertEq(IERC20(WETH).allowance(UNISWAP_ROUTER, address(s_feeAggregatorReceiver)), 0);
  }

  /**
   * When the feed price is stale, performUpkeep() should soft revert for the ABT.
   * Given:
   *  amountOut for WETH is below deviation threshold.
   * Expected:
   *  InsufficientAmountReceived() error should be swallowed and the swap and transfer of WETH
   * should be reverted.
   */
  function test_performUpkeep_SingleSwapSinglePool_PostSwapAmountOutBelowMaxDeviation()
    public
    givenAssetEligibleForSwap(WETH)
  {
    // GIVEN
    (, bytes memory data) = _checkUpkeepWithSimulation();
    uint256 amountIn = IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver));
    uint256 abtAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(WETH).usdFeed);
    uint256 amountOutFromFeed = _getExpectedAmountOutLinkFromFeed(amountIn, abtAssetPrice, IERC20Metadata(WETH));

    // WHEN: Uniswap Router returns amountOut that's below minimum accepted post-swap deviation
    // threshold.
    uint256 mockAmountBelowDeviationThreshold =
      amountOutFromFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_PRICE_DEVIATION * 2);
    vm.mockCall(
      UNISWAP_ROUTER,
      abi.encodeWithSelector(IV3SwapRouter.exactInput.selector),
      abi.encode(mockAmountBelowDeviationThreshold)
    );

    /**
     * EXPECTED:
     * 1. InsufficientAmountReceived() error should be swallowed and the ETH swap and transfer
     * should be reverted.
     * 2. Since AllSwaps within performUpkeep only contain one failing swap, AllSwapsFailed() error
     * should be thrown.
     */
    vm.expectRevert(SwapAutomator.AllSwapsFailed.selector);
    s_swapAutomator.performUpkeep(data);

    // ABT should be transfer back to receiver contract and the allowance should be
    // reverted/decreased.
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), amountIn);
    assertEq(IERC20(WETH).allowance(UNISWAP_ROUTER, address(s_feeAggregatorReceiver)), 0);
  }

  /**
   * When amountOut from uniswapRouter is below deviation threshold, performUpkeep() should soft
   * revert for an ABT.
   * Given:
   *  amountOut for WETH is below deviation threshold.
   *  amountOut for USDC is happy-path, above both deviation threshold and slippage threshold.
   * Expected:
   *  InsufficientAmountReceived() error should be swallowed and the swap and transfer of WETH
   * should be reverted.
   *  Swap for USDC should
   */
  function test_performUpkeep_MultipleSwaps_PartialFailurePostSwapAmountOutBelowMaxDeviation()
    public
    givenAssetEligibleForSwap(WETH)
    givenAssetEligibleForSwap(USDC)
  {
    (, bytes memory data) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(data, (IV3SwapRouter.ExactInputParams[]));

    uint256 amountInWeth = IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver));
    uint256 amountInUsdc = IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver));
    uint256 wethAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(WETH).usdFeed);
    uint256 usdcAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(USDC).usdFeed);
    uint256 usdcSwapValue = usdcAssetPrice * amountInUsdc;

    uint256 amountOutWethFromFeed =
      _getExpectedAmountOutLinkFromFeed(amountInWeth, wethAssetPrice, IERC20Metadata(WETH));

    // WHEN: amountOut for WETH is below deviation threshold.
    uint256 mockAmountOutWETHBelowDeviationThreshold =
      amountOutWethFromFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_PRICE_DEVIATION * 2);
    vm.mockCall(
      UNISWAP_ROUTER,
      abi.encodeWithSelector(IV3SwapRouter.exactInput.selector, swapInputs[0]),
      abi.encode(mockAmountOutWETHBelowDeviationThreshold)
    );

    /**
     * EXPECTED:
     * 1. InsufficientAmountReceived() error should be swallowed and the ETH swap and transfer
     * should be reverted.
     * 2. swap for USDC should succeed.
     */
    vm.expectEmit(true, true, false, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, USDC, amountInUsdc, 0);
    s_swapAutomator.performUpkeep(data);

    // WETH should be transfer back to receiver contract and the allowance should be
    // reverted/decreased.
    // USDC swap should succeed.
    uint256 linkBalanceValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED)) * IERC20(LINK).balanceOf(i_receiver);
    uint256 minValue = usdcSwapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);
    assert(linkBalanceValue >= minValue);

    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), amountInWeth);
    assertEq(IERC20(WETH).allowance(UNISWAP_ROUTER, address(s_feeAggregatorReceiver)), 0);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(WETH), 0);
    assertEq(IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(USDC), block.timestamp);
  }

  function test_performUpkeep_SingleSwapSinglePool() public givenAssetEligibleForSwap(WETH) {
    (, bytes memory data) = _checkUpkeepWithSimulation();
    uint256 amountIn = IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver));
    uint256 abtAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(WETH).usdFeed);
    uint256 swapValue = abtAssetPrice * amountIn;
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(WETH);
    (uint256 amountOutUniswapQuote,,,) = s_swapAutomator.getUniswapQuoterV2().quoteExactInput(swapParams.path, amountIn);
    uint256 amountOutFromFeed = _getExpectedAmountOutLinkFromFeed(amountIn, abtAssetPrice, IERC20Metadata(WETH));

    // Ignore topic 3 as the value will only be know post swap
    vm.expectEmit(true, true, false, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, WETH, amountIn, 0);
    s_swapAutomator.performUpkeep(data);

    uint256 linkBalanceValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED)) * IERC20(LINK).balanceOf(i_receiver);
    uint256 minValue = swapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);
    uint256 minAmountOutValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED))
      * Math.max(amountOutFromFeed, amountOutUniswapQuote).percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);

    assert(linkBalanceValue >= minValue);
    assert(linkBalanceValue >= minAmountOutValue); //Asserting that the actual swapped LINK
    // amountOut is
    // greater than calculated minAmountOut
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(WETH), block.timestamp);
  }

  function test_performUpkeep_SingleSwapMultiplePools() public givenAssetEligibleForSwap(USDC) {
    (, bytes memory data) = _checkUpkeepWithSimulation();

    uint256 amountIn = IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver));
    uint256 abtAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(USDC).usdFeed);
    uint256 swapValue = abtAssetPrice * amountIn;
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(USDC);
    (uint256 amountOutUniswapQuote,,,) = s_swapAutomator.getUniswapQuoterV2().quoteExactInput(swapParams.path, amountIn);
    uint256 amountOutFromFeed = _getExpectedAmountOutLinkFromFeed(amountIn, abtAssetPrice, IERC20Metadata(USDC));

    // Ignore topic 3 as the value will only be know post swap
    vm.expectEmit(true, true, false, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, USDC, amountIn, 0);
    s_swapAutomator.performUpkeep(data);

    uint256 linkBalanceValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED)) * IERC20(LINK).balanceOf(i_receiver);
    uint256 minValue = swapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);
    uint256 minAmountOutValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED))
      * Math.max(amountOutFromFeed, amountOutUniswapQuote).percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);

    assert(linkBalanceValue >= minValue);
    assert(linkBalanceValue >= minAmountOutValue); //Asserting that the actual swapped LINK
    // amountOut is
    // greater than calculated minAmountOut
    assertEq(IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(USDC), block.timestamp);
  }

  function test_performUpkeep_MultipleSwaps() public givenAssetEligibleForSwap(WETH) givenAssetEligibleForSwap(USDC) {
    (, bytes memory data) = _checkUpkeepWithSimulation();
    uint256 amountInWeth = IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver));
    uint256 amountInUsdc = IERC20(USDC).balanceOf(address(s_feeAggregatorReceiver));
    uint256 wethAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(WETH).usdFeed);
    uint256 usdcAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(USDC).usdFeed);
    uint256 wethSwapValue = wethAssetPrice * amountInWeth;
    uint256 usdcSwapValue = usdcAssetPrice * amountInUsdc;
    uint256 totalSwapValue = wethSwapValue + usdcSwapValue;
    SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(WETH);
    (uint256 amountOutWethUniswapQuote,,,) =
      s_swapAutomator.getUniswapQuoterV2().quoteExactInput(swapParams.path, amountInWeth);
    uint256 amountOutWethFromFeed =
      _getExpectedAmountOutLinkFromFeed(amountInWeth, wethAssetPrice, IERC20Metadata(WETH));
    swapParams = s_swapAutomator.getAssetSwapParams(USDC);
    (uint256 amountOutUsdcUniswapQuote,,,) =
      s_swapAutomator.getUniswapQuoterV2().quoteExactInput(swapParams.path, amountInUsdc);
    uint256 amountOutUsdcFromFeed =
      _getExpectedAmountOutLinkFromFeed(amountInUsdc, usdcAssetPrice, IERC20Metadata(USDC));

    // Ignore topic 3 as the value will only be know post swap
    vm.expectEmit(true, true, false, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, WETH, amountInWeth, 0);
    vm.expectEmit(true, true, false, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, USDC, amountInUsdc, 0);
    s_swapAutomator.performUpkeep(data);

    uint256 linkBalanceValue =
      _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED)) * IERC20(LINK).balanceOf(address(i_receiver));
    uint256 minValue = totalSwapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);

    uint256 totalMinAmountOut = Math.max(amountOutWethUniswapQuote, amountOutWethFromFeed)
      + Math.max(amountOutUsdcUniswapQuote, amountOutUsdcFromFeed);
    uint256 totalMinAmountOutValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED))
      * totalMinAmountOut.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);

    assert(linkBalanceValue >= minValue);
    assert(linkBalanceValue >= totalMinAmountOutValue); //Asserting that the actual swapped LINK
    // amountOut is
    // greater than calculated minAmountOut
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(WETH), block.timestamp);
    assertEq(s_swapAutomator.getLatestSwapTimestamp(USDC), block.timestamp);
  }

  function test_performUpkeep_SwapAllAbts() public {
    address[] memory allowlistedAssets = s_feeAggregatorReceiver.getAllowlistedAssets();
    uint256 totalSwapValue;
    uint256 totalMinAmountOut;

    for (uint256 i = 0; i < allowlistedAssets.length; ++i) {
      _dealSwapAmount(allowlistedAssets[i], address(s_feeAggregatorReceiver), MIN_SWAP_SIZE * 2);
      uint256 amountIn = IERC20(allowlistedAssets[i]).balanceOf(address(s_feeAggregatorReceiver));
      uint256 assetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(allowlistedAssets[i]).usdFeed);
      uint256 swapValue = assetPrice * amountIn;
      totalSwapValue += swapValue;
      uint256 amountOutUniswapQuote;
      if (allowlistedAssets[i] != LINK) {
        SwapAutomator.SwapParams memory swapParams = s_swapAutomator.getAssetSwapParams(allowlistedAssets[i]);
        (amountOutUniswapQuote,,,) = s_swapAutomator.getUniswapQuoterV2().quoteExactInput(swapParams.path, amountIn);
      }
      uint256 amountOutFromFeed =
        _getExpectedAmountOutLinkFromFeed(amountIn, assetPrice, IERC20Metadata(allowlistedAssets[i]));
      totalMinAmountOut +=
        Math.max(amountOutFromFeed, amountOutUniswapQuote).percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);
    }

    (, bytes memory data) = _checkUpkeepWithSimulation();
    s_swapAutomator.performUpkeep(data);

    uint256 linkBalanceValue =
      _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED)) * IERC20(LINK).balanceOf(address(i_receiver));
    uint256 minValue = totalSwapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);
    uint256 totalMinAmountOutValue = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED))
      * totalMinAmountOut.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_SLIPPAGE);

    assert(linkBalanceValue >= minValue);
    assert(linkBalanceValue >= totalMinAmountOutValue); //Asserting that the actual swapped LINK
    // amountOut is
    // greater than calculated minAmountOut
    for (uint256 i = 0; i < allowlistedAssets.length; ++i) {
      assertEq(IERC20(allowlistedAssets[i]).balanceOf(address(s_feeAggregatorReceiver)), 0);
      if (allowlistedAssets[i] != LINK) {
        assertEq(s_swapAutomator.getLatestSwapTimestamp(allowlistedAssets[i]), block.timestamp);
      }
    }
  }

  function test_performUpkeep_Usdt_TradeSuccess() public givenAssetEligibleForSwap(USDT) {
    // 1) Get the performData by simulating checkUpkeep()
    (bool shouldExecute, bytes memory performData) = _checkUpkeepWithSimulation();
    assertTrue(shouldExecute, "Should have upkeep for USDT trade test");

    // 2) Record aggregator's USDT balance before swapping
    uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(s_feeAggregatorReceiver));
    assertGt(usdtBalanceBefore, 0, "Expected aggregator to hold some USDT beforehand");

    // 3) Expect a SwapAutomator.AssetSwapped event for USDT
    //    (We ignore the unindexed fields by setting checkData = false.)
    vm.expectEmit(true, true, true, false, address(s_swapAutomator));
    emit SwapAutomator.AssetSwapped(i_receiver, USDT, 0, 0);

    // 4) Execute the swap
    s_swapAutomator.performUpkeep(performData);

    // 5) Verify aggregator’s USDT was swapped out
    assertEq(
      IERC20(USDT).balanceOf(address(s_feeAggregatorReceiver)), 0, "Expected aggregator to have 0 USDT after swap"
    );

    // 6) Confirm the SwapAutomator recorded a “latest swap timestamp” for USDT
    assertEq(s_swapAutomator.getLatestSwapTimestamp(USDT), block.timestamp, "USDT lastSwapTimestamp mismatch");
  }

  function test_performUpkeep_MultipleSwaps_PartialFailurePostSwapAmountOutBelowMaxDeviation_USDT()
    public
    givenAssetEligibleForSwap(WETH)
    givenAssetEligibleForSwap(USDT)
  {
    // ------------------------------------------------------
    // PART A: Setup & partial fail scenario
    // ------------------------------------------------------
    // 1) Check upkeep => get "performData" with 2 swaps (WETH, USDT).
    (, bytes memory data) = _checkUpkeepWithSimulation();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = abi.decode(data, (IV3SwapRouter.ExactInputParams[]));
    require(swapInputs.length == 2, "Expected exactly 2 swaps: WETH + USDT");

    // 2) Gather balances & prices
    uint256 amountInUsdt = IERC20(USDT).balanceOf(address(s_feeAggregatorReceiver));
    uint256 usdtAssetPrice = _getAssetPrice(s_swapAutomator.getAssetSwapParams(USDT).usdFeed);

    // 3) We let aggregator swap WETH first with no mocking => success

    // 4) Then aggregator tries USDT => we force partial fail by mocking "insufficient" return
    uint256 usdtSwapValue = usdtAssetPrice * amountInUsdt;
    uint256 mockAmountOutUSDTBelowDeviation =
      usdtSwapValue.percentMul(PercentageMath.PERCENTAGE_FACTOR - MAX_PRICE_DEVIATION * 2);

    // We assume swapInputs[1] is USDT => mock to fail
    vm.mockCall(
      UNISWAP_ROUTER,
      abi.encodeWithSelector(IV3SwapRouter.exactInput.selector, swapInputs[1]),
      abi.encode(mockAmountOutUSDTBelowDeviation)
    );

    // 5) performUpkeep => WETH swapped => USDT fails
    s_swapAutomator.performUpkeep(data);

    // 6) Checks after partial fail:
    //    - aggregator WETH => 0 => lastSwapTimestamp updated
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), 0, "WETH should be swapped out fully");
    assertEq(s_swapAutomator.getLatestSwapTimestamp(WETH), block.timestamp, "WETH partial fail => not expected");

    //    - aggregator USDT => unchanged => no lastSwapTimestamp
    assertEq(IERC20(USDT).balanceOf(address(s_feeAggregatorReceiver)), amountInUsdt, "USDT remains after partial fail");
    assertEq(s_swapAutomator.getLatestSwapTimestamp(USDT), 0, "USDT partial fail => no timestamp update");

    // ------------------------------------------------------
    // PART B: Now do a new pass that successfully swaps USDT
    // ------------------------------------------------------

    // 7) aggregator STILL has USDT => aggregator sees new upkeep => it tries just USDT now
    //    Because aggregator's WETH is already zero, the aggregator only sees USDT left to swap.
    //    So let's check again, with no mocking => let aggregator succeed USDT this time.
    vm.clearMockedCalls();

    // 8) Re-run _checkUpkeepWithSimulation => aggregator sees single swap: USDT
    (bool shouldExecute2, bytes memory data2) = _checkUpkeepWithSimulation();
    assertTrue(shouldExecute2, "Expected aggregator to have upkeep for USDT again");

    IV3SwapRouter.ExactInputParams[] memory swapInputs2 = abi.decode(data2, (IV3SwapRouter.ExactInputParams[]));
    // we expect a single swap now (just USDT)
    require(swapInputs2.length == 1, "Expected exactly 1 swap: USDT this time");

    // 9) aggregator performUpkeep => this time the USDT swap is not mocked => aggregator succeeds
    s_swapAutomator.performUpkeep(data2);

    // 10) Final checks: aggregator’s USDT => 0 => aggregator sets lastSwapTimestamp(USDT)
    assertEq(
      IERC20(USDT).balanceOf(address(s_feeAggregatorReceiver)),
      0,
      "Expected aggregator to have 0 USDT after second swap"
    );
    assertEq(
      s_swapAutomator.getLatestSwapTimestamp(USDT),
      block.timestamp,
      "Expected aggregator to update lastSwapTimestamp(USDT) after success"
    );
  }

  /// @custom:see SwapAutomator._convertToLink();
  function _getExpectedAmountOutLinkFromFeed(
    uint256 amount,
    uint256 assetPrice,
    IERC20Metadata asset
  ) private view returns (uint256) {
    uint256 tokenDecimals = asset.decimals();
    uint256 linkUSDPrice = _getAssetPrice(AggregatorV3Interface(LINK_USD_FEED));
    if (tokenDecimals < 18) {
      return (amount * assetPrice * 10 ** (18 - tokenDecimals)) / linkUSDPrice;
    } else {
      return (amount * assetPrice) / linkUSDPrice / 10 ** (tokenDecimals - 18);
    }
  }

  function _checkUpkeepWithSimulation() internal returns (bool, bytes memory) {
    // Changing the msg.sender and tx.origin to simulation add since checkUpKeep() is cannotExecute
    _changePrank(AUTOMATION_SIMULATION_ADDRESS, AUTOMATION_SIMULATION_ADDRESS);
    (bool shouldExecute, bytes memory data) = s_swapAutomator.checkUpkeep("");
    _changePrank(i_forwarder);
    return (shouldExecute, data);
  }
}
