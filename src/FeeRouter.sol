// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {LinkReceiver} from "src/LinkReceiver.sol";
import {NativeTokenReceiver} from "src/NativeTokenReceiver.sol";
import {Common} from "src/libraries/Common.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";

import {ITypeAndVersion} from "@chainlink/contracts/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice The FeeRouter contract acts as a buffer between service contracts and the FeeAggregtor contract. The
/// motivation for such behavior is to avoid automatic flow of fees into the payment abstraction system.
contract FeeRouter is ITypeAndVersion, EmergencyWithdrawer, LinkReceiver, NativeTokenReceiver {
  using SafeERC20 for IERC20;

  /// @notice Parameters to instantiate the contract in the constructor
  // solhint-disable-next-line gas-struct-packing
  struct ConstructorParams {
    /// @notice The minimum amount of seconds that must pass before
    /// the admin address can be transferred
    uint48 adminRoleTransferDelay;
    /// @notice The initial contract admin
    address admin;
    /// @notice The Fee Aggregator
    address feeAggregator;
    /// @notice LINK token
    address linkToken;
    /// @notice The wrapped native token
    address wrappedNativeToken;
  }

  /// @notice This event is emitted when an asset is transferred
  /// @notice to the specified address
  /// @param asset The address of the  asset that was transferred
  /// @param amount The amount of asset that was transferred
  event AssetTransferred(address indexed to, address indexed asset, uint256 amount);
  /// @notice This event is emitted when a non allowlisted asset is withdrawn
  /// @param to The address that received the withdrawn asset
  /// @param asset The address of the asset that was withdrawn - address(0) is used for native token
  /// @param amount The amount of assets that was withdrawn
  event NonAllowlistedAssetWithdrawn(address indexed to, address indexed asset, uint256 amount);
  /// @notice This event is emitted when a new fee aggregator receiver is set/
  /// @param feeAggregatorReceiver The address of the fee aggregator receiver
  event FeeAggregatorSet(address feeAggregatorReceiver);

  string public constant override typeAndVersion = "FeeRouter v1.0.0";

  /// @notice The fee aggregator receiver contract
  IFeeAggregator private s_feeAggregator;

  constructor(
    ConstructorParams memory params
  )
    EmergencyWithdrawer(params.adminRoleTransferDelay, params.admin)
    LinkReceiver(params.linkToken)
    NativeTokenReceiver(params.wrappedNativeToken)
  {
    _setFeeAggregator(params.feeAggregator);
  }

  // ================================================================
  // ||                      Asset Transfers                       ||
  // ================================================================

  /// @dev Transfers allowlisted assets to the fee aggregator
  /// @dev precondition - the caller must have the BRIDGER_ROLE
  /// @dev precondition - the contract must not be paused
  /// @dev precondition - the list of assetAmounts must not be empty
  /// @dev precondition - the transferred assets must be allowlisted
  /// @param assetAmounts The list of allowlisted assets and amounts to transfer
  function transferAllowlistedAssets(
    Common.AssetAmount[] calldata assetAmounts
  ) external onlyRole(Roles.BRIDGER_ROLE) whenNotPaused {
    if (assetAmounts.length == 0) {
      revert Errors.EmptyList();
    }

    IFeeAggregator feeAggregator = s_feeAggregator;

    for (uint256 i; i < assetAmounts.length; ++i) {
      address asset = assetAmounts[i].asset;

      if (!feeAggregator.isAssetAllowlisted(asset)) {
        revert Errors.AssetNotAllowlisted(asset);
      }

      uint256 amount = assetAmounts[i].amount;

      _transferAsset(address(feeAggregator), asset, amount);
      emit AssetTransferred(address(feeAggregator), asset, amount);
    }
  }

  /// @dev Withdraws non allowlisted assets from the contract
  /// @dev precondition - The contract must not be paused
  /// @dev precondition - The caller must have the WITHDRAWER_ROLE
  /// @dev precondition - The list of assetAmounts must not be empty
  /// @dev precondition - The withdrawn assets must not be allowlisted
  /// @param assetAmounts The list of non allowlisted assets and amounts to withdraw
  function withdrawNonAllowlistedAssets(
    address to,
    Common.AssetAmount[] calldata assetAmounts
  ) external whenNotPaused onlyRole(Roles.WITHDRAWER_ROLE) {
    if (assetAmounts.length == 0) {
      revert Errors.EmptyList();
    }

    IFeeAggregator feeAggregator = s_feeAggregator;

    for (uint256 i; i < assetAmounts.length; ++i) {
      address asset = assetAmounts[i].asset;

      if (feeAggregator.isAssetAllowlisted(asset)) {
        revert Errors.AssetAllowlisted(asset);
      }

      uint256 amount = assetAmounts[i].amount;

      _transferAsset(to, asset, amount);

      emit NonAllowlistedAssetWithdrawn(to, asset, amount);
    }
  }

  /// @notice Withdraws native tokens from the contract to the specified address
  /// @dev precondition - The contract must not be paused
  /// @dev precondition - The caller must have the WITHDRAWER_ROLE
  /// @param to The address to transfer the native tokens to
  /// @param amount The amount of native tokens to transfer
  function withdrawNative(address payable to, uint256 amount) external whenNotPaused onlyRole(Roles.WITHDRAWER_ROLE) {
    address wrappedNativeToken = address(s_wrappedNativeToken);

    if (s_feeAggregator.isAssetAllowlisted(wrappedNativeToken)) {
      revert Errors.AssetAllowlisted(wrappedNativeToken);
    }

    _transferNative(to, amount);
    emit NonAllowlistedAssetWithdrawn(msg.sender, address(0), amount);
  }

  // ================================================================
  // ||                           Config                           ||
  // ================================================================

  /// @dev Sets the fee aggregator
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The new fee aggregator must not be the zero address
  /// @dev precondition The new fee aggregator must be different from the current fee aggregator
  /// @param feeAggregator The address of the new fee FeeAggregatorSet
  function setFeeAggregator(
    address feeAggregator
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setFeeAggregator(feeAggregator);
  }

  function _setFeeAggregator(
    address newFeeAggregator
  ) internal {
    if (newFeeAggregator == address(0)) {
      revert Errors.InvalidZeroAddress();
    }
    if (newFeeAggregator == address(s_feeAggregator)) {
      revert Errors.ValueNotUpdated();
    }
    if (!IERC165(newFeeAggregator).supportsInterface(type(IFeeAggregator).interfaceId)) {
      revert Errors.InvalidFeeAggregator(newFeeAggregator);
    }

    s_feeAggregator = IFeeAggregator(newFeeAggregator);

    emit FeeAggregatorSet(newFeeAggregator);
  }

  /// @notice Getter function to retrieve the configured fee aggregator receiver
  /// @return feeAggregator The configured fee aggregator receiver
  function getFeeAggregator() external view returns (IFeeAggregator feeAggregator) {
    return s_feeAggregator;
  }

  /// @dev Sets the wrapped native token.
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev The wrapped native token should be set to the same address as the one in the FeeAggregator contract. This
  /// check is performed offchain.
  /// @param wrappedNativeToken The wrapped native token address.
  function setWrappedNativeToken(
    address wrappedNativeToken
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setWrappedNativeToken(wrappedNativeToken);
  }
}
