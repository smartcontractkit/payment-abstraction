// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Common} from "src/libraries/Common.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";

import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {AutomationCompatibleInterface} from
  "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ITypeAndVersion} from "@chainlink/contracts/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

/// @notice Chainlink Automation upkeep implementation contract that automates swapping of FeeAggregator assets
/// into LINK by utilising Uniswap V3.
contract SwapAutomator is ITypeAndVersion, PausableWithAccessControl, AutomationCompatible {
  using PercentageMath for uint256;
  using SafeCast for int256;
  using SafeERC20 for IERC20;

  /// @notice This event is emitted when the LINK token address is set
  /// @param linkToken The LINK token address
  event LinkTokenSet(address indexed linkToken);
  /// @notice This event is emitted when the LINK/USD price feed address is set
  /// @param linkUsdFeed The address of the LINK/USD price feed
  event LINKUsdFeedSet(address indexed linkUsdFeed);
  /// @notice This event is emitted when the Uniswap Router address is set
  /// @param uniswapRouter The address of the Uniswap Router
  event UniswapRouterSet(address indexed uniswapRouter);
  /// @notice This event is emitted when the Uniswap Quoter V2 address is set
  /// @param uniswapQuoterV2 The address of the Uniswap QuoterV2
  event UniswapQuoterV2Set(address indexed uniswapQuoterV2);
  /// @notice This event is emitted when a new forwarder is set
  /// @param forwarder The address of the new forwarder
  event ForwarderSet(address forwarder);
  /// @notice This event is emitted when a new fee aggregator receiver
  /// is set
  /// @param feeAggregator The address of the fee aggregator
  event FeeAggregatorSet(address feeAggregator);
  /// @notice This event is emitted when an asset is converted to LINK
  /// @param recipient The address that received the swapped LINK
  /// @param asset The address of the asset
  /// @param amountIn The amount of assets converted to LINK
  /// @param amountOut The amount of LINK received after swapping
  event AssetSwapped(address indexed recipient, address indexed asset, uint256 amountIn, uint256 amountOut);
  /// @notice This event is emitted when new swap parameters are set for an asset
  /// @param asset The address of the asset
  /// @param params The swap parameters
  event AssetSwapParamsUpdated(address asset, SwapParams params);
  /// @notice This event is emitted when swap parameters are removed for an asset
  /// @param asset The address of the asset
  event AssetSwapParamsRemoved(address asset);
  /// @notice This event is emitted when a new deadline delay is set
  /// @param newDeadlinDelay The new deadline delay
  event DeadlineDelaySet(uint96 newDeadlinDelay);
  /// @notice This event is emitted when as swap fails
  /// @param asset The address of the asset that failed to swap
  /// @param swapInput The swap input that failed
  event AssetSwapFailure(address indexed asset, IV3SwapRouter.ExactInputParams swapInput);
  /// @notice This event is emitted when the address that will receive swapped
  /// LINK is set
  /// @param linkReceiver The address that will receive swapped LINK
  event LinkReceiverSet(address indexed linkReceiver);
  /// @notice This event is emitted when the LINK token decimals are set in the constructor
  /// @param decimals The LINK token decimals
  event LinkDecimalsSet(uint256 decimals);
  /// @notice This event is emitted when the LINK/USD feed decimals are set in the constructor
  /// @param decimals The LINK/USD feed decimals
  event LinkUsdFeedDecimalsSet(uint256 decimals);
  /// @notice This event is emitted when the maximum size of the perform data is set
  /// @param maxPerformDataSize The maximum size of the perform data
  event MaxPerformDataSizeSet(uint256 maxPerformDataSize);

  /// @notice This error is thrown when max slippage parameter set is 0, or above 100%
  /// @param maxSlippage value for max slippage passed into function
  error InvalidSlippage(uint16 maxSlippage);
  /// @notice This error is thrown when the max price deviation is set below the max slippage, or above 100%
  /// @param maxPriceDeviation value for max price deviation passed into function
  error InvalidMaxPriceDeviation(uint16 maxPriceDeviation);
  /// @notice This error is thrown when the min swap size is zero or greater than the max swap size
  error InvalidMinSwapSizeUsd();
  /// @notice This error is thrown when trying to set an empty swap path
  error EmptySwapPath();
  /// @notice This error is thrown when trying to set the deadline delay to a value lower than the
  /// minimum threshold
  error DeadlineDelayTooLow(uint96 deadlineDelay, uint96 minDeadlineDelay);
  /// @notice This error is thrown when trying to set the deadline delay to a value higher than the
  /// maximum threshold
  error DeadlineDelayTooHigh(uint96 deadlineDelay, uint96 maxDeadlineDelay);
  /// @notice This error is thrown when the transaction timestamp is greater than the deadline
  error TransactionTooOld(uint256 timestamp, uint256 deadline);
  /// @notice This error is thrown when the swap path is invalid as compared to the swap path set by
  /// the Admin.
  error InvalidSwapPath();
  /// @notice This error is thrown when the recipent of the swap param does not match the receiver's
  /// @param feeRecipient address of the fee recipient passed into function
  error FeeRecipientMismatch(address feeRecipient);
  /// @notice This error is thrown when all performed swaps have failed
  error AllSwapsFailed();
  /// @notice This error is thrown when the amount received from a swap is less than the minimum
  /// @param amountOut Uniswap extracted amount out
  /// @param minAmount Minimum amount required for swap
  error InsufficientAmountReceived(uint256 amountOut, uint256 minAmount);

  /// @notice Parameters to instantiate the contract in the constructor
  /* solhint-disable-next-line gas-struct-packing */
  struct ConstructorParams {
    uint48 adminRoleTransferDelay; // ─╮ The minimum amount of seconds that must pass before the admin address can be
    //                                 │ transferred
    address admin; // ─────────────────╯ The initial contract admin
    uint96 deadlineDelay; // ──────────╮ The maximum amount of seconds the swap transaction is valid for
    address linkToken; // ─────────────╯ The Link token
    address feeAggregator; //            The Fee Aggregator
    address linkUsdFeed; //              The link usd feed
    address uniswapRouter; //            The address of the Uniswap router
    address uniswapQuoterV2; //          The address of the Uniswap QuoterV2
    address linkReceiver; //             The address that will receive converted LINK
    uint256 maxPerformDataSize; //       The maximum size of the perform data passed to the performUpkeep function
  }

  /// @notice The parameters to perform a swap
  struct SwapParams {
    AggregatorV3Interface usdFeed; // ─╮ The asset usd feed
    uint16 maxSlippage; //             │ The maximum allowed slippage for the swap in basis points
    uint16 maxPriceDeviation; //       │ The maximum allowed one-side deviation of actual swapped out amount
    //                                 │ vs CLprice feed estimated amount, in basis points
    uint32 swapInterval; //            │ The minimum interval between swaps
    uint32 stalenessThreshold; // ─────╯ The staleness threshold for price feed data
    uint128 minSwapSizeUsd; // ────────╮ The minimum swap size expressed in USD feed decimals
    uint128 maxSwapSizeUsd; // ────────╯ The maximum swap size expressed in USD feed decimals
    bytes path; // The swap path
  }

  /// @notice Contains the swap parameters for an asset
  struct AssetSwapParamsArgs {
    address asset; // The asset
    SwapParams swapParams; // The asset's swap parameters
  }

  /// @inheritdoc ITypeAndVersion
  string public constant override typeAndVersion = "Uniswap V3 Swap Automator 1.0.0";
  /// @notice The lower bound for the deadline delay
  uint96 private constant MIN_DEADLINE_DELAY = 1 minutes;
  /// @notice The upper bound for the deadline delay
  uint96 private constant MAX_DEADLINE_DELAY = 1 hours;

  /// @notice The link token
  LinkTokenInterface private immutable i_linkToken;
  /// @notice The address of the chainlink USD feed
  AggregatorV3Interface private immutable i_linkUsdFeed;
  /// @notice The address of the Uniswap router
  IV3SwapRouter private immutable i_uniswapRouter;
  /// @notice The address of the Uniswap QuoterV2
  IQuoterV2 private immutable i_uniswapQuoterV2;
  /// @notice The number of decimals for the LINK token
  uint256 private immutable i_linkDecimals;
  /// @notice The number of decimals for the LINK/USD feed
  uint256 private immutable i_linkUsdFeedDecimals;

  /// @notice The address will execute the automation job
  address private s_forwarder;
  /// @notice The maximum amount of seconds the swap transaction is valid for
  uint96 private s_deadlineDelay;

  /// @notice The fee aggregator
  IFeeAggregator private s_feeAggregator;
  /// @notice The receiver of LINK tokens
  address private s_linkReceiver;
  /// @notice The maximum size of the perform data passed to the performUpkeep function
  uint256 private s_maxPerformDataSize;

  /// @notice Mapping of assets to their swap parameters
  mapping(address asset => SwapParams swapParams) private s_assetSwapParams;
  /// @notice Mapping of assets to their lastest swap timestamp
  mapping(address asset => uint256 latestSwapTimestamp) private s_latestSwapTimestamp;
  /// @notice Mapping of assets to their hashed swap path
  mapping(address asset => bytes32 hashedSwapPath) private s_assetHashedSwapPath;

  constructor(
    ConstructorParams memory params
  ) PausableWithAccessControl(params.adminRoleTransferDelay, params.admin) {
    if (
      params.linkToken == address(0) || params.linkUsdFeed == address(0) || params.uniswapRouter == address(0)
        || params.uniswapQuoterV2 == address(0)
    ) {
      revert Errors.InvalidZeroAddress();
    }

    i_linkToken = LinkTokenInterface(params.linkToken);
    i_linkUsdFeed = AggregatorV3Interface(params.linkUsdFeed);
    i_uniswapRouter = IV3SwapRouter(params.uniswapRouter);
    i_uniswapQuoterV2 = IQuoterV2(params.uniswapQuoterV2);
    i_linkDecimals = IERC20Metadata(params.linkToken).decimals();
    i_linkUsdFeedDecimals = AggregatorV3Interface(params.linkUsdFeed).decimals();

    emit LinkTokenSet(params.linkToken);
    emit LINKUsdFeedSet(params.linkUsdFeed);
    emit UniswapRouterSet(params.uniswapRouter);
    emit UniswapQuoterV2Set(params.uniswapQuoterV2);
    emit LinkDecimalsSet(i_linkDecimals);
    emit LinkUsdFeedDecimalsSet(i_linkUsdFeedDecimals);

    _setFeeAggregator(params.feeAggregator);
    _setDeadlineDelay(params.deadlineDelay);
    _setLinkReceiver(params.linkReceiver);
    _setMaxPerformDataSize(params.maxPerformDataSize);
  }

  /// @notice Set the address that `performUpkeep` is called from
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The contract must not be paused
  /// @dev precondition The forwarder address must not be the zero address
  /// @param forwarder the address to set
  function setForwarder(
    address forwarder
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (forwarder == address(0)) {
      revert Errors.InvalidZeroAddress();
    }
    if (s_forwarder == forwarder) {
      revert Errors.ValueNotUpdated();
    }
    s_forwarder = forwarder;
    emit ForwarderSet(forwarder);
  }

  /// @notice Sets and removes swap parameters for assets
  /// @dev precondition The caller must have the ASSET_ADMIN_ROLE
  /// @dev precondition The assets must be allowlisted on the FeeAggregator
  /// @dev precondition The asset list length must match the params list length
  /// @dev precondition The assets feed addresses must not be the zero address
  /// @dev precondition The assets token address must not be the zero address
  /// @dev precondition The assets maxSlippage must be greater than 0
  /// @param assetsToRemove The list of assets to remove swap parameters
  /// @param assetSwapParamsArgs The asset swap parameters arguments
  function applyAssetSwapParamsUpdates(
    address[] calldata assetsToRemove,
    AssetSwapParamsArgs[] calldata assetSwapParamsArgs
  ) external onlyRole(Roles.ASSET_ADMIN_ROLE) {
    // process removals first
    for (uint256 i; i < assetsToRemove.length; ++i) {
      delete s_assetSwapParams[assetsToRemove[i]];
      delete s_assetHashedSwapPath[assetsToRemove[i]];

      emit AssetSwapParamsRemoved(assetsToRemove[i]);
    }

    IFeeAggregator feeAggregator = s_feeAggregator;

    for (uint256 i; i < assetSwapParamsArgs.length; ++i) {
      SwapParams memory assetSwapParams = assetSwapParamsArgs[i].swapParams;
      address assetAddress = assetSwapParamsArgs[i].asset;

      if (!feeAggregator.isAssetAllowlisted(assetAddress)) {
        revert Errors.AssetNotAllowlisted(assetAddress);
      }
      if (address(assetSwapParams.usdFeed) == address(0)) {
        revert Errors.InvalidZeroAddress();
      }
      if (assetSwapParams.maxSlippage == 0 || assetSwapParams.maxSlippage >= PercentageMath.PERCENTAGE_FACTOR) {
        revert InvalidSlippage(assetSwapParams.maxSlippage);
      }
      if (
        assetSwapParams.maxPriceDeviation < assetSwapParams.maxSlippage
          || assetSwapParams.maxPriceDeviation >= PercentageMath.PERCENTAGE_FACTOR
      ) {
        revert InvalidMaxPriceDeviation(assetSwapParams.maxPriceDeviation);
      }
      if (assetSwapParams.stalenessThreshold == 0) {
        revert Errors.InvalidZeroAmount();
      }
      if (assetSwapParams.minSwapSizeUsd == 0 || assetSwapParams.minSwapSizeUsd > assetSwapParams.maxSwapSizeUsd) {
        revert InvalidMinSwapSizeUsd();
      }
      if (assetSwapParams.path.length == 0) {
        revert EmptySwapPath();
      }

      s_assetSwapParams[assetAddress] = assetSwapParams;
      s_assetHashedSwapPath[assetAddress] = keccak256(assetSwapParams.path);

      emit AssetSwapParamsUpdated(assetAddress, assetSwapParams);
    }
  }

  /// @notice Gets the swap params for an asset
  /// @param asset The address of the asset
  /// @return swapParams The swap parameters for the asset
  function getAssetSwapParams(
    address asset
  ) external view returns (SwapParams memory swapParams) {
    return s_assetSwapParams[asset];
  }

  /// @notice Sets the fee aggregator receiver
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The new fee aggregator address must
  /// not be the zero address
  /// @dev precondition The new fee aggregator address must be
  /// different from the already configured fee aggregator
  function setFeeAggregator(
    address feeAggregator
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setFeeAggregator(feeAggregator);
  }

  /// @notice Sets the fee aggregator
  /// @param feeAggregator The new fee aggregator
  function _setFeeAggregator(
    address feeAggregator
  ) internal {
    if (feeAggregator == address(0)) {
      revert Errors.InvalidZeroAddress();
    }
    if (address(s_feeAggregator) == feeAggregator) {
      revert Errors.ValueNotUpdated();
    }
    if (!IERC165(feeAggregator).supportsInterface(type(IFeeAggregator).interfaceId)) {
      revert Errors.InvalidFeeAggregator(feeAggregator);
    }

    s_feeAggregator = IFeeAggregator(feeAggregator);

    emit FeeAggregatorSet(feeAggregator);
  }

  /// @notice Sets a new deadline delay
  /// @dev precondition The caller must have the ASSET_ADMIN_ROLE
  /// @dev precondition The new deadline delay must be lower or equal than the maximum deadline
  /// delay
  /// @dev precondition The new deadline delay must be different from the already set deadline delay
  /// @param deadlineDelay The new deadline delay
  function setDeadlineDelay(
    uint96 deadlineDelay
  ) external onlyRole(Roles.ASSET_ADMIN_ROLE) {
    _setDeadlineDelay(deadlineDelay);
  }

  /// @notice Sets the deadline delay
  /// @param deadlineDelay The new deadline delay
  function _setDeadlineDelay(
    uint96 deadlineDelay
  ) internal {
    if (s_deadlineDelay == deadlineDelay) {
      revert Errors.ValueNotUpdated();
    }
    if (deadlineDelay < MIN_DEADLINE_DELAY) {
      revert DeadlineDelayTooLow(deadlineDelay, MIN_DEADLINE_DELAY);
    }
    if (deadlineDelay > MAX_DEADLINE_DELAY) {
      revert DeadlineDelayTooHigh(deadlineDelay, MAX_DEADLINE_DELAY);
    }

    s_deadlineDelay = deadlineDelay;
    emit DeadlineDelaySet(deadlineDelay);
  }

  /// @notice Sets the maximum size of the perform data passed to the performUpkeep function
  /// @dev precondition - The caller must have the DEFAULT_ADMIN_ROLE
  /// @param maxPerformDataSize The maximum size of the perform data
  function setMaxPerformDataSize(
    uint256 maxPerformDataSize
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMaxPerformDataSize(maxPerformDataSize);
  }

  /// @notice Sets the maximum size of the perform data passed to the performUpkeep function
  /// @dev precondition - The new maximum size must be greater than 0
  /// @dev precondition - The new maximum size must different than the old one
  /// @param maxPerformDataSize The maximum size of the perform data
  function _setMaxPerformDataSize(
    uint256 maxPerformDataSize
  ) internal {
    if (maxPerformDataSize == 0) {
      revert Errors.InvalidZeroAmount();
    }
    if (maxPerformDataSize == s_maxPerformDataSize) {
      revert Errors.ValueNotUpdated();
    }

    s_maxPerformDataSize = maxPerformDataSize;
    emit MaxPerformDataSizeSet(maxPerformDataSize);
  }

  /// @notice Getter function to retrieve the maximum perform data size
  /// @return maxPrformDataSize the maximum data size that the performUpkeep function accepts
  function getMaxPerformDataSize() external view returns (uint256 maxPrformDataSize) {
    return s_maxPerformDataSize;
  }

  /// @notice Getter function to retrieve the LINK/USD feed
  /// @return linkUsdFeed The LINK/USD feed
  function getLINKUsdFeed() external view returns (AggregatorV3Interface linkUsdFeed) {
    return i_linkUsdFeed;
  }

  /// @notice Getter function to retrieve the address that `performUpkeep` is called from
  /// @return forwarder The address that `performUpkeep` is called from
  function getForwarder() external view returns (address forwarder) {
    return s_forwarder;
  }

  /// @notice Getter function to retrieve the LINK token used
  /// @return linkToken The LINK token
  function getLinkToken() external view returns (LinkTokenInterface linkToken) {
    return i_linkToken;
  }

  /// @notice Getter function to retrieve the Uniswap Router used for swaps
  /// @return uniswapRouter The Uniswap Router
  function getUniswapRouter() external view returns (IV3SwapRouter uniswapRouter) {
    return i_uniswapRouter;
  }

  /// @notice Getter function to retrieve the Uniswap QuoterV2 used for quotes
  /// @return uniswapQuoter The Uniswap QuoterV2
  function getUniswapQuoterV2() external view returns (IQuoterV2 uniswapQuoter) {
    return i_uniswapQuoterV2;
  }

  /// @notice Getter function to retrieve the configured fee aggregator
  /// @return feeAggregator The configured fee aggregator
  function getFeeAggregator() external view returns (IFeeAggregator feeAggregator) {
    return s_feeAggregator;
  }

  /// @notice Getter function to retrieve the latest swap timestamp for an asset
  /// @param asset The address of the asset
  /// @return latestSwapTimestamp Latest swap timestamp for an asset, or 0 if never swapped
  function getLatestSwapTimestamp(
    address asset
  ) external view returns (uint256 latestSwapTimestamp) {
    return s_latestSwapTimestamp[asset];
  }

  /// @notice Getter function to retrieve the deadline delay
  /// @return deadlineDelay The deadline delay
  function getDeadlineDelay() external view returns (uint96 deadlineDelay) {
    return s_deadlineDelay;
  }

  /// @notice Getter function to retrieve the hash of the registered swap path given an asset
  /// @return hashedSwapPath The hashed swap path, 0 if asset is unregistered.
  function getHashedSwapPath(
    address asset
  ) external view returns (bytes32 hashedSwapPath) {
    return s_assetHashedSwapPath[asset];
  }

  /// @notice Getter function to retrieve the configured LINK receiver
  /// @return linkReceiver The address of the receiver
  function getLinkReceiver() external view returns (address linkReceiver) {
    return s_linkReceiver;
  }

  /// @notice Sets the address that will receive swapped LINK
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The LINK receiver address must not be the zero address
  /// @dev precondition The LINK receiver address must be different from the already configured one
  /// @param linkReceiver The address of the address that will
  /// receive swapped LINK
  function setLinkReceiver(
    address linkReceiver
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setLinkReceiver(linkReceiver);
  }

  /// @notice Sets the address that will receive swapped LINK
  /// @param linkReceiver The address of the address that will
  /// receive swapped LINK
  function _setLinkReceiver(
    address linkReceiver
  ) internal {
    if (linkReceiver == address(0)) {
      revert Errors.InvalidZeroAddress();
    }
    if (linkReceiver == s_linkReceiver) {
      revert Errors.ValueNotUpdated();
    }

    s_linkReceiver = linkReceiver;

    emit LinkReceiverSet(linkReceiver);
  }

  // ================================================================
  // │                Swap Logic And Automation                     │
  // ================================================================

  /// @inheritdoc AutomationCompatibleInterface
  /* solhint-disable-next-line chainlink-solidity/explicit-returns */
  function checkUpkeep(
    bytes calldata
  ) external whenNotPaused cannotExecute returns (bool upkeepNeeded, bytes memory performData) {
    address[] memory allowlistedAssets = s_feeAggregator.getAllowlistedAssets();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = new IV3SwapRouter.ExactInputParams[](allowlistedAssets.length);
    address receiver = s_linkReceiver;
    uint256 idx;
    uint256 linkUSDPrice = _getValidatedAssetPrice(address(i_linkToken), i_linkUsdFeed);
    // The fixed size of the performData is 3 * 32 = 96 bytes corresponding to:
    // - slot 0: the offset to the encoded data
    // - slot 1: the deadlineDelay
    // - slot 2: the length of the swapInputs array
    uint256 performDataSize = 96;

    for (uint256 i; i < allowlistedAssets.length; ++i) {
      address asset = allowlistedAssets[i];

      SwapParams memory swapParams = s_assetSwapParams[asset];

      if (swapParams.usdFeed == AggregatorV3Interface(address(0))) {
        continue;
      }

      (uint256 assetPrice, uint256 updatedAt) = _getAssetPrice(swapParams.usdFeed);

      if (assetPrice == 0 || updatedAt < block.timestamp - swapParams.stalenessThreshold) {
        continue;
      }

      uint256 assetUnit = 10 ** IERC20Metadata(asset).decimals();

      // 1) Get the current asset value in USD available in the FeeAggregator
      uint256 availableAssetUsdValue = IERC20(asset).balanceOf(address(s_feeAggregator)) * assetPrice;

      // 2) Don't swap asset if the asset's current USD balance on this FeeAggregator is
      // below the minimum swap amount or if insufficient time has elapsed since the last swap
      if (
        availableAssetUsdValue >= swapParams.minSwapSizeUsd * assetUnit
          && block.timestamp - s_latestSwapTimestamp[asset] >= swapParams.swapInterval
      ) {
        // 3) Determine the swap amountIn
        uint256 swapAmountIn = Math.min(swapParams.maxSwapSizeUsd * assetUnit, availableAssetUsdValue) / assetPrice;

        // 4) Quote the amountOut from both Uniswap V3 quoter and CL price feed for all ADTs
        // except LINK
        uint256 amountOutUniswapQuote;
        uint256 amountOutCLPriceFeedQuote =
          _convertToLink(swapAmountIn, assetPrice, swapParams.usdFeed.decimals(), linkUSDPrice, IERC20Metadata(asset));

        if (asset != address(i_linkToken)) {
          (amountOutUniswapQuote,,,) = i_uniswapQuoterV2.quoteExactInput(swapParams.path, swapAmountIn);

          // 5) If amountOutUniswapQuote is below the amountOutPriceFeed with slippage, do not
          // perform swap for this asset.
          if (
            amountOutUniswapQuote
              < amountOutCLPriceFeedQuote.percentMul(PercentageMath.PERCENTAGE_FACTOR - swapParams.maxSlippage)
          ) {
            continue;
          }
        }

        // We increment the performDataSize by:
        // - 6 * 32 = 192 bytes corresponding to:
        //    - slot 3: the offset to the struct data
        //    - slot 4: the offset to the path
        //    - slot 5: the recipient
        //    - slot 6: the amountIn
        //    - slot 7: the amountOutMinimum
        //    - slot 8: the path length
        // - The number of slots required for the path:
        //    - path.length / 32 * 32 -> the rounded down number of slots required
        //    - path.length % 32 > 0 ? 32 : 0 -> +1 slot if the path length is not a multiple of 32
        performDataSize += 192 + (swapParams.path.length / 32) * 32 + (swapParams.path.length % 32 > 0 ? 32 : 0);

        // 6) If the performDataSize exceeds the maximum size, break out of the loop
        if (performDataSize > s_maxPerformDataSize) {
          break;
        }

        swapInputs[idx++] = IV3SwapRouter.ExactInputParams({
          path: swapParams.path,
          recipient: receiver,
          amountIn: swapAmountIn,
          // 7) Determine the minimum amount of juels we expect to get back by applying slippage to
          // the greater of two quotes.
          amountOutMinimum: Math.max(amountOutUniswapQuote, amountOutCLPriceFeedQuote).percentMul(
            PercentageMath.PERCENTAGE_FACTOR - swapParams.maxSlippage
          )
        });
      }
    }

    if (idx != allowlistedAssets.length) {
      assembly {
        // Update executeSwapData length
        mstore(swapInputs, idx)
      }
    }

    // Using if/else here to avoid abi.encoding empty bytes when idx = 0
    if (idx > 0) {
      return (true, abi.encode(swapInputs, block.timestamp + s_deadlineDelay));
    } else {
      return (false, "");
    }
  }

  /// @inheritdoc AutomationCompatibleInterface
  /// @dev precondition The caller must be the forwarder
  function performUpkeep(
    bytes calldata performData
  ) external whenNotPaused {
    if (msg.sender != s_forwarder) {
      revert Errors.AccessForbidden();
    }

    (IV3SwapRouter.ExactInputParams[] memory swapInputs, uint256 deadline) =
      abi.decode(performData, (IV3SwapRouter.ExactInputParams[], uint256));

    if (deadline < block.timestamp) {
      revert TransactionTooOld(block.timestamp, deadline);
    }

    bool success;
    address linkReceiver = s_linkReceiver;
    uint256 linkPriceFromFeed = _getValidatedAssetPrice(address(i_linkToken), i_linkUsdFeed);

    Common.AssetAmount[] memory assetAmounts = new Common.AssetAmount[](swapInputs.length);

    for (uint256 i; i < swapInputs.length; ++i) {
      assetAmounts[i] =
        Common.AssetAmount({asset: address(bytes20(swapInputs[i].path)), amount: swapInputs[i].amountIn});
    }

    IFeeAggregator feeAggregator = s_feeAggregator;

    feeAggregator.transferForSwap(address(this), assetAmounts);

    // This may run into out of gas errors but the likelihood is low as there
    // will not be too many assets to swap to LINK
    for (uint256 i; i < swapInputs.length; ++i) {
      bytes memory assetSwapPath = swapInputs[i].path;
      address asset = assetAmounts[i].asset;

      if (keccak256(assetSwapPath) != s_assetHashedSwapPath[asset]) {
        revert InvalidSwapPath();
      }

      if (swapInputs[i].recipient != linkReceiver) {
        revert FeeRecipientMismatch(swapInputs[i].recipient);
      }

      // Pull tokens from the FeeAggregator
      uint256 amountIn = swapInputs[i].amountIn;

      // NOTE: LINK is expected to be configured with static values:
      // pool: LINK -> LINK
      // maxSlippage: 1
      // maxSwapSizeUsd: type(uint128).max
      // swapInterval: 0
      if (asset == address(i_linkToken)) {
        IERC20(asset).safeTransfer(linkReceiver, amountIn);
        success = true;
      } else {
        IERC20(asset).safeIncreaseAllowance(address(i_uniswapRouter), amountIn);
        // For multiple swaps we don't want to revert the whole transaction if only some of the
        // swaps
        // fail so we catch the revert and continue with the next swap
        try this.swapWithPriceFeedValidation(swapInputs[i], asset, linkPriceFromFeed) returns (uint256 amountOut) {
          s_latestSwapTimestamp[asset] = block.timestamp;
          success = true;
          emit AssetSwapped(swapInputs[i].recipient, asset, amountIn, amountOut);
        } catch {
          IERC20(asset).safeDecreaseAllowance(address(i_uniswapRouter), amountIn);

          // Transfer failed swap amount back to the FeeAggregator
          IERC20(asset).safeTransfer(address(feeAggregator), amountIn);

          emit AssetSwapFailure(asset, swapInputs[i]);
        }
      }
    }

    // If all swaps have failed, revert the transaction
    if (!success) {
      revert AllSwapsFailed();
    }
  }

  /// @notice Helper function that executes the swap and check the swap amountOut against ADT & LINK
  /// price feed.
  /// @param swapInput The swapInput for Uniswap Router
  /// @param asset The address of the asset to be swapped.
  /// @param linkPriceFromFeed The price of Link from price feed
  /// @return amountOut Swapped out token amount
  function swapWithPriceFeedValidation(
    IV3SwapRouter.ExactInputParams calldata swapInput,
    address asset,
    uint256 linkPriceFromFeed
  ) external returns (uint256 amountOut) {
    if (msg.sender != address(this)) {
      revert Errors.AccessForbidden();
    }
    amountOut = i_uniswapRouter.exactInput(swapInput);

    SwapParams memory swapParams = s_assetSwapParams[asset];
    uint256 assetPriceFromPriceFeed = _getValidatedAssetPrice(asset, swapParams.usdFeed);
    uint256 linkAmountOutFromPriceFeed = _convertToLink(
      swapInput.amountIn,
      assetPriceFromPriceFeed,
      swapParams.usdFeed.decimals(),
      linkPriceFromFeed,
      IERC20Metadata(asset)
    );

    if (
      amountOut < linkAmountOutFromPriceFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - swapParams.maxPriceDeviation)
    ) {
      revert InsufficientAmountReceived(
        amountOut,
        linkAmountOutFromPriceFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - swapParams.maxPriceDeviation)
      );
    }
    return amountOut;
  }

  /// @notice Helper function to fetch an asset price
  /// @param usdFeed The USD price feed to fetch the price from
  /// @return assetPrice The asset price
  /// @return updatedAtTimestamp Timestamp at which the price was last updated
  function _getAssetPrice(
    AggregatorV3Interface usdFeed
  ) private view returns (uint256 assetPrice, uint256 updatedAtTimestamp) {
    (, int256 answer,, uint256 updatedAt,) = usdFeed.latestRoundData();
    return (answer.toUint256(), updatedAt);
  }

  /// @notice Helper function to fetch the LINK price, with feed staleness & answer validation
  /// @param asset The asset to fetch the price for
  /// @param usdFeed The USD price feed to fetch the price from
  /// @return assetPrice The asset price
  function _getValidatedAssetPrice(
    address asset,
    AggregatorV3Interface usdFeed
  ) private view returns (uint256 assetPrice) {
    (uint256 answer, uint256 updatedAt) = _getAssetPrice(usdFeed);

    if (answer == 0) {
      revert Errors.ZeroFeedData();
    }
    if (updatedAt < block.timestamp - s_assetSwapParams[asset].stalenessThreshold) {
      revert Errors.StaleFeedData();
    }

    return answer;
  }

  /// @notice Helper function to convert an asset amount to Juels denomination
  /// @param assetAmount The amount to convert
  /// @param asset The asset to convert
  /// @param assetPrice The asset price in USD
  /// @param assetFeedDecimals The asset feed decimals
  /// @param linkUSDPrice The LINK price in USD
  /// @return linkAmount The converted amount in Juels
  /* solhint-disable-next-line chainlink-solidity/explicit-returns */
  function _convertToLink(
    uint256 assetAmount,
    uint256 assetPrice,
    uint256 assetFeedDecimals,
    uint256 linkUSDPrice,
    IERC20Metadata asset
  ) private view returns (uint256 linkAmount) {
    // Scale feed decimals
    // In order to account for different decimals between the asset and the LINK/USD feed and avoid losing precision, we
    // scale the smallest decimal feed to the largest one.
    if (assetFeedDecimals > i_linkUsdFeedDecimals) {
      linkUSDPrice = linkUSDPrice * 10 ** (assetFeedDecimals - i_linkUsdFeedDecimals);
    } else if (assetFeedDecimals < i_linkUsdFeedDecimals) {
      assetPrice = assetPrice * 10 ** (i_linkUsdFeedDecimals - assetFeedDecimals);
    }

    uint256 tokenDecimals = asset.decimals();
    // Once prices are scaled, we can convert the asset amount to LINK.
    // Since the returned ammount is in LINK, token decimals must also be taken into consideration to scale the result
    // up or down.
    // Note: asset price & link USD price are normalized to the same units from the previous step.
    if (tokenDecimals < i_linkDecimals) {
      // X = linkDecimals
      // Y = tokenDecimals
      // Z = decimals for assetPrice & linkPrice
      // AA = assetAmount
      // LP = linkPrice
      // AP = assetPrice

      // (AA * 10**Y * AP * 10**Z * 10**(X - Y)) / (LP * 10**Z)
      // (AA * 10**(Y + X - Y) * AP * 10**Z) / (LP * 10**Z)
      // (AA * 10**X * AP * 10**Z) / (LP * 10**Z)
      // (AA * 10**X) * (AP * 10**Z) / (LP * 10**Z)
      // (AA * 10**X) * (AP / LP)
      return (assetAmount * assetPrice * 10 ** (i_linkDecimals - tokenDecimals)) / linkUSDPrice;
    } else {
      // X = linkDecimals
      // Y = tokenDecimals
      // Z = decimals for assetPrice & linkPrice
      // AA = assetAmount
      // LP = linkPrice
      // AP = assetPrice

      // ((AA * 10**Y * AP * 10**Z) / (LP * 10**Z)) / (10**(Y - X))
      // ((AA * 10**Y * AP) / LP) / (10**(Y - X))
      // ((AA * 10**Y) * (AP / LP)) / (10**(Y - X))
      // ((AA * (AP / LP)) * 10**Y) / (10**(Y - X))
      // (AA * (AP / LP) * 10**(Y - (Y - X)))
      // (AA * (AP / LP)) * 10**(Y - Y + X)
      // (AA * (AP / LP)) * 10**X
      // (AA * 10**X) * (AP / LP)
      return ((assetAmount * assetPrice) / linkUSDPrice) / (10 ** (tokenDecimals - i_linkDecimals));
    }
  }
}
