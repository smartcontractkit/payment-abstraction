// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {FeeAggregator} from "src/FeeAggregator.sol";
import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract SwapAutomator is ITypeAndVersion, PausableWithAccessControl, AutomationCompatible {
  using PercentageMath for uint256;
  using SafeCast for int256;
  using SafeERC20 for IERC20;

  /// @notice This event is emitted when the LINK token address is set
  /// @param linkToken The LINK token address
  event LINKTokenSet(address indexed linkToken);
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

  /// @notice Parameters to instantiate the contract in the constructor
  /* solhint-disable gas-struct-packing */
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
  }
  /* solhint-enable gas-struct-packing */

  /// @notice The parameters to perform a swap
  struct SwapParams {
    AggregatorV3Interface oracle; // ─╮ The asset usd oracle
    uint16 maxSlippage; //            │ The maximum allowed slippage for the swap in basis points
    uint16 maxPriceDeviation; //      │  The maximum allowed one-side deviation of actual swapped out amount
    //                                │  vs CL oracle price feed estimated amount
    uint64 swapInterval; // ──────────╯ The minimum interval between swaps
    uint128 minSwapSizeUsd; // ───────╮ The minimum swap size expressed in USD 8 decimals
    uint128 maxSwapSizeUsd; // ───────╯ The maximum swap size expressed in USD 8 decimals
    bytes path; //                      The swap path
  }

  /// @notice Contains the swap parameters for a list of assets
  struct AssetSwapParamsArgs {
    address[] assets; // The list of assets
    SwapParams[] assetsSwapParams; // The list of swap parameters
  }

  /// @inheritdoc ITypeAndVersion
  string public constant override typeAndVersion = "Uniswap V3 Swap Automator 1.0.0";
  /// @notice The staleness threshold for oracles data
  /// @dev The threshold is set to 1 day to match the Chainlink feeds heartbeat requirement
  uint256 private constant STALENESS_THRESHOLD = 1 days;
  /// @notice The number of decimals for the LINK token
  uint256 private constant LINK_DECIMALS = 18;
  /// @notice The lower bound for the deadline delay
  uint96 private constant MIN_DEADLINE_DELAY = 1 minutes;
  /// @notice The upper bound for the deadline delay
  uint96 private constant MAX_DEADLINE_DELAY = 1 hours;

  /// @notice The link token
  LinkTokenInterface private immutable i_LINK;
  /// @notice The address of the chainlink USD oracle
  AggregatorV3Interface private immutable i_linkUsdFeed;
  /// @notice The address of the Uniswap router
  IV3SwapRouter private immutable i_uniswapRouter;
  /// @notice The address of the Uniswap QuoterV2
  IQuoterV2 private immutable i_uniswapQuoterV2;

  /// @notice The address will execute the automation job
  address private s_forwarder;
  /// @notice The maximum amount of seconds the swap transaction is valid for
  uint96 private s_deadlineDelay;
  /// @notice The fee aggregator
  IFeeAggregator private s_feeAggregator;
  /// @notice Mapping of assets to their swap parameters
  address private s_linkReceiver;

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

    i_LINK = LinkTokenInterface(params.linkToken);
    i_linkUsdFeed = AggregatorV3Interface(params.linkUsdFeed);
    i_uniswapRouter = IV3SwapRouter(params.uniswapRouter);
    i_uniswapQuoterV2 = IQuoterV2(params.uniswapQuoterV2);
    _setFeeAggregator(params.feeAggregator);
    _setDeadlineDelay(params.deadlineDelay);
    _setLinkReceiver(params.linkReceiver);
    emit LINKTokenSet(params.linkToken);
    emit LINKUsdFeedSet(params.linkUsdFeed);
    emit UniswapRouterSet(params.uniswapRouter);
    emit UniswapQuoterV2Set(params.uniswapQuoterV2);
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
      revert Errors.ForwarderNotUpdated();
    }
    s_forwarder = forwarder;
    emit ForwarderSet(forwarder);
  }

  /// @notice Sets and removes swap parameters for assets
  /// @dev precondition The caller must have the ASSET_ADMIN_ROLE
  /// @dev precondition The assets must be allowlisted on the FeeAggregator
  /// @dev precondition The asset list length must match the params list length
  /// @dev precondition The assets oracle addresses must not be the zero address
  /// @dev precondition The assets token address must not be the zero address
  /// @dev precondition The assets maxSlippage must be greater than 0
  /// @param assetsToRemove The list of assets to remove swap parameters
  /// @param assetSwapParamsArgs The asset swap parameters arguments
  function applyAssetSwapParamsUpdates(
    address[] calldata assetsToRemove,
    AssetSwapParamsArgs calldata assetSwapParamsArgs
  ) external onlyRole(Roles.ASSET_ADMIN_ROLE) {
    // process removals first
    for (uint256 i; i < assetsToRemove.length; ++i) {
      delete s_assetSwapParams[assetsToRemove[i]];
      delete s_assetHashedSwapPath[assetsToRemove[i]];

      emit AssetSwapParamsRemoved(assetsToRemove[i]);
    }

    // process updates next
    if (assetSwapParamsArgs.assets.length != assetSwapParamsArgs.assetsSwapParams.length) {
      revert Errors.AssetsSwapParamsMismatch();
    }

    (bool areAssetsAllowlisted, address nonAllowlistedAsset) =
      s_feeAggregator.areAssetsAllowlisted(assetSwapParamsArgs.assets);

    if (!areAssetsAllowlisted) {
      revert Errors.AssetNotAllowlisted(nonAllowlistedAsset);
    }

    for (uint256 i; i < assetSwapParamsArgs.assetsSwapParams.length; ++i) {
      if (address(assetSwapParamsArgs.assetsSwapParams[i].oracle) == address(0)) {
        revert Errors.InvalidZeroAddress();
      }
      if (
        assetSwapParamsArgs.assetsSwapParams[i].maxSlippage == 0
          || assetSwapParamsArgs.assetsSwapParams[i].maxSlippage >= PercentageMath.PERCENTAGE_FACTOR
      ) {
        revert Errors.InvalidSlippage();
      }
      if (assetSwapParamsArgs.assetsSwapParams[i].path.length == 0) {
        revert Errors.EmptySwapPath();
      }

      s_assetSwapParams[assetSwapParamsArgs.assets[i]] = assetSwapParamsArgs.assetsSwapParams[i];
      s_assetHashedSwapPath[assetSwapParamsArgs.assets[i]] = keccak256(assetSwapParamsArgs.assetsSwapParams[i].path);

      emit AssetSwapParamsUpdated(assetSwapParamsArgs.assets[i], assetSwapParamsArgs.assetsSwapParams[i]);
    }
  }

  /// @notice Gets the swap params for an asset
  /// @param asset The address of the asset
  /// @return SwapParams The swap parameters for the asset
  function getAssetSwapParams(
    address asset
  ) external view returns (SwapParams memory) {
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
    if (feeAggregator == address(0)) revert Errors.InvalidZeroAddress();
    if (address(s_feeAggregator) == feeAggregator) {
      revert Errors.FeeAggregatorNotUpdated();
    }
    s_feeAggregator = FeeAggregator(feeAggregator);
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
      revert Errors.DeadlineDelayNotUpdated();
    }
    if (deadlineDelay < MIN_DEADLINE_DELAY) {
      revert Errors.DeadlineDelayTooLow(deadlineDelay, MIN_DEADLINE_DELAY);
    }
    if (deadlineDelay > MAX_DEADLINE_DELAY) {
      revert Errors.DeadlineDelayTooHigh(deadlineDelay, MAX_DEADLINE_DELAY);
    }

    s_deadlineDelay = deadlineDelay;
    emit DeadlineDelaySet(deadlineDelay);
  }

  /// @notice Getter function to retrieve the LINK/USD feed
  /// @return AggregatorV3Interface The LINK/USD feed
  function getLINKUsdFeed() external view returns (AggregatorV3Interface) {
    return i_linkUsdFeed;
  }

  /// @notice Getter function to retrieve the address that `performUpkeep` is called from
  /// @return address The address that `performUpkeep` is called from
  function getForwarder() external view returns (address) {
    return s_forwarder;
  }

  /// @notice Getter function to retrieve the LINK token used
  /// @return LinkTokenInterface The LINK token
  function getLINK() external view returns (LinkTokenInterface) {
    return i_LINK;
  }

  /// @notice Getter function to retrieve the Uniswap Router used for swaps
  /// @return IV3SwapRouter The Uniswap Router
  function getUniswapRouter() external view returns (IV3SwapRouter) {
    return i_uniswapRouter;
  }

  /// @notice Getter function to retrieve the Uniswap QuoterV2 used for quotes
  /// @return IQuoterV2 The Uniswap QuoterV2
  function getUniswapQuoterV2() external view returns (IQuoterV2) {
    return i_uniswapQuoterV2;
  }

  /// @notice Getter function to retrieve the configured fee aggregator
  /// @return IFeeAggregator The configured fee aggregator
  function getFeeAggregator() external view returns (IFeeAggregator) {
    return s_feeAggregator;
  }

  /// @notice Getter function to retrieve the latest swap timestamp for an asset
  /// @param asset The address of the asset
  function getLatestSwapTimestamp(
    address asset
  ) external view returns (uint256) {
    return s_latestSwapTimestamp[asset];
  }

  /// @notice Getter function to retrieve the deadline delay
  /// @return uint96 The deadline delay
  function getDeadlineDelay() external view returns (uint96) {
    return s_deadlineDelay;
  }

  /// @notice Getter function to retrieve the hash of the registered swap path given an asset
  /// @return bytes32 The hashed swap path, 0 if asset is unregistered.
  function getHashedSwapPath(
    address asset
  ) external view returns (bytes32) {
    return s_assetHashedSwapPath[asset];
  }

  /// @notice Getter function to retrieve the configured LINK receiver
  /// @return address The address of the receiver
  function getLinkReceiver() external view returns (address) {
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
      revert Errors.LINKReceiverNotUpdated();
    }

    s_linkReceiver = linkReceiver;

    emit LinkReceiverSet(linkReceiver);
  }

  // ================================================================
  // │                Swap Logic And Automation                     │
  // ================================================================

  /// @inheritdoc AutomationCompatibleInterface
  function checkUpkeep(
    bytes calldata
  ) external whenNotPaused cannotExecute returns (bool, bytes memory) {
    address[] memory allowlistedAssets = s_feeAggregator.getAllowlistedAssets();
    IV3SwapRouter.ExactInputParams[] memory swapInputs = new IV3SwapRouter.ExactInputParams[](allowlistedAssets.length);
    address receiver = s_linkReceiver;
    uint256 idx;
    uint256 linkUSDPrice = _getValidatedLINKFeedPrice();

    for (uint256 i; i < allowlistedAssets.length; ++i) {
      address asset = allowlistedAssets[i];

      SwapParams memory swapParams = s_assetSwapParams[asset];

      if (swapParams.oracle == AggregatorV3Interface(address(0))) {
        continue;
      }

      (uint256 assetPrice, uint256 updatedAt) = _getAssetPrice(AggregatorV3Interface(swapParams.oracle));

      if (assetPrice == 0 || updatedAt < block.timestamp - STALENESS_THRESHOLD) continue;
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

        // 4) Quote the amountOut from both Uniswap V3 quoter and CL oracle price feed for all ADTs
        // except LINK
        uint256 amountOutUniswapQuote;
        uint256 amountOutCLPriceFeedQuote =
          _convertToLink(swapAmountIn, assetPrice, linkUSDPrice, IERC20Metadata(asset));

        if (asset != address(i_LINK)) {
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

        swapInputs[idx++] = IV3SwapRouter.ExactInputParams({
          path: swapParams.path,
          recipient: receiver,
          amountIn: swapAmountIn,
          // 6) Determine the minimum amount of juels we expect to get back by applying slippage to
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
      revert Errors.TransactionTooOld(block.timestamp, deadline);
    }

    bool success;
    address linkReceiver = s_linkReceiver;
    uint256 linkPriceFromFeed = _getValidatedLINKFeedPrice();

    address[] memory assets = new address[](swapInputs.length);
    uint256[] memory amounts = new uint256[](swapInputs.length);

    for (uint256 i; i < swapInputs.length; ++i) {
      assets[i] = address(bytes20(swapInputs[i].path));
      amounts[i] = swapInputs[i].amountIn;
    }

    IFeeAggregator feeAggregator = s_feeAggregator;

    feeAggregator.transferForSwap(address(this), assets, amounts);

    // This may run into out of gas errors but the likelihood is low as there
    // will not be too many assets to swap to LINK
    for (uint256 i; i < swapInputs.length; ++i) {
      bytes memory assetSwapPath = swapInputs[i].path;
      address asset = assets[i];

      if (keccak256(assetSwapPath) != s_assetHashedSwapPath[asset]) {
        revert Errors.InvalidSwapPath();
      }

      if (swapInputs[i].recipient != linkReceiver) {
        revert Errors.FeeRecipientMismatch();
      }

      // Pull tokens from the FeeAggregator
      uint256 amountIn = swapInputs[i].amountIn;

      // NOTE: LINK is expected to be configured with static values:
      // pool: LINK -> LINK
      // maxSlippage: 1
      // maxSwapSizeUsd: type(uint128).max
      // swapInterval: 0
      if (asset == address(i_LINK)) {
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
      revert Errors.AllSwapsFailed();
    }
  }

  /// @notice Helper function that executes the swap and check the swap amountOut against ADT & LINK
  /// price feed.
  /// @param swapInput The swapInput for Uniswap Router
  /// @param asset The address of the asset to be swapped.
  /// @param linkPriceFromFeed The price of Link from price feed
  /// @return uint256 Swapped out token amount
  function swapWithPriceFeedValidation(
    IV3SwapRouter.ExactInputParams calldata swapInput,
    address asset,
    uint256 linkPriceFromFeed
  ) external returns (uint256) {
    if (msg.sender != address(this)) {
      revert Errors.AccessForbidden();
    }
    uint256 amountOut = i_uniswapRouter.exactInput(swapInput);

    SwapParams memory swapParams = s_assetSwapParams[asset];
    (uint256 assetPriceFromPriceFeed,) = _getAssetPrice(AggregatorV3Interface(swapParams.oracle));
    uint256 linkAmountOutFromPriceFeed =
      _convertToLink(swapInput.amountIn, assetPriceFromPriceFeed, linkPriceFromFeed, IERC20Metadata(asset));

    if (
      amountOut < linkAmountOutFromPriceFeed.percentMul(PercentageMath.PERCENTAGE_FACTOR - swapParams.maxPriceDeviation)
    ) {
      revert Errors.InsufficientAmountReceived();
    }
    return amountOut;
  }

  /// @notice Helper function to fetch an asset price
  /// @param oracle The oracle to fetch the price from
  /// @return uint256 The asset price
  function _getAssetPrice(
    AggregatorV3Interface oracle
  ) private view returns (uint256, uint256) {
    (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
    return (answer.toUint256(), updatedAt);
  }

  /// @notice Helper function to fetch the LINK price, with oracle staleness & answer validation
  function _getValidatedLINKFeedPrice() private view returns (uint256) {
    (uint256 answer, uint256 updatedAt) = _getAssetPrice(i_linkUsdFeed);

    if (answer == 0) revert Errors.ZeroOracleData();
    if (updatedAt < block.timestamp - STALENESS_THRESHOLD) {
      revert Errors.StaleOracleData();
    }

    return answer;
  }

  /// @notice Helper function to convert an asset amount to Juels denomination
  /// @param assetAmount The amount to convert
  /// @param asset The asset to convert
  /// @param assetPrice The asset price in USD
  /// @param linkUSDPrice The LINK price in USD
  /// @return uint256 The converted amount in Juels
  function _convertToLink(
    uint256 assetAmount,
    uint256 assetPrice,
    uint256 linkUSDPrice,
    IERC20Metadata asset
  ) private view returns (uint256) {
    uint256 tokenDecimals = asset.decimals();

    if (tokenDecimals < LINK_DECIMALS) {
      return (assetAmount * assetPrice * 10 ** (LINK_DECIMALS - tokenDecimals)) / linkUSDPrice;
    } else {
      return (assetAmount * assetPrice) / linkUSDPrice / 10 ** (tokenDecimals - LINK_DECIMALS);
    }
  }
}
