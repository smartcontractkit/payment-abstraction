// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {LinkReceiver} from "src/LinkReceiver.sol";
import {NativeTokenReceiver} from "src/NativeTokenReceiver.sol";
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

  /// @notice This error is thrown when setting a fee aggregator that does not support the IFeeAggregator interface
  error InvalidFeeAggregator(address feeAggregator);

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
    if (params.feeAggregator == address(0)) {
      revert Errors.InvalidZeroAddress();
    }

    s_feeAggregator = IFeeAggregator(params.feeAggregator);

    emit FeeAggregatorSet(params.feeAggregator);
  }

  // ================================================================
  // ||                      Asset Transfers                       ||
  // ================================================================

  /// @dev Transfers allowlisted assets to the fee aggregator
  /// @dev precondition - the caller must have the BRIDGER_ROLE
  /// @dev precondition - the contract must not be paused
  /// @dev precondition - the transferred assets must be allowlisted
  /// @param assets The list of allowlisted assets to transfer
  /// @param amounts The list of allowlisted asset amounts to transfer
  function transferAllowlistedAssets(
    address[] calldata assets,
    uint256[] calldata amounts
  ) external onlyRole(Roles.BRIDGER_ROLE) whenNotPaused {
    _validateAssetTransferInputs(assets, amounts);

    IFeeAggregator feeAggregator = s_feeAggregator;

    (bool areAssetsAllowlisted, address nonAllowlistedAsset) = feeAggregator.areAssetsAllowlisted(assets);

    if (!areAssetsAllowlisted) {
      revert Errors.AssetNotAllowlisted(nonAllowlistedAsset);
    }

    for (uint256 i = 0; i < assets.length; ++i) {
      address asset = assets[i];
      uint256 amount = amounts[i];

      _transferAsset(address(feeAggregator), asset, amount);
      emit AssetTransferred(address(feeAggregator), asset, amount);
    }
  }

  /// @dev Withdraws non allowlisted assets from the contract
  /// @dev precondition The caller must have the WITHDRAWER_ROLE
  /// @dev precondition The list of WithdrawAssetAmount must not be empty
  /// @dev precondition The withdrawn assets must not be allowlisted
  /// @param assets The list of non allowlisted assets to withdraw
  /// @param amounts The list of non allowlisted asset amounts to withdraw
  function withdrawNonAllowlistedAssets(
    address to,
    address[] calldata assets,
    uint256[] calldata amounts
  ) external onlyRole(Roles.WITHDRAWER_ROLE) {
    _validateAssetTransferInputs(assets, amounts);

    IFeeAggregator feeAggregator = s_feeAggregator;

    (bool areAssetsAllowlisted,) = feeAggregator.areAssetsAllowlisted(assets);

    if (areAssetsAllowlisted) {
      revert Errors.AssetAllowlisted(assets[0]);
    }

    for (uint256 i = 0; i < assets.length; ++i) {
      address asset = assets[i];
      uint256 amount = amounts[i];

      _transferAsset(to, asset, amount);
      emit NonAllowlistedAssetWithdrawn(msg.sender, asset, amount);
    }
  }

  /// @notice Withdraws native tokens from the contract to the specified address
  /// @dev precondition The caller must have the WITHDRAWER_ROLE
  /// @param to The address to transfer the native tokens to
  /// @param amount The amount of native tokens to transfer
  function withdrawNative(address payable to, uint256 amount) external onlyRole(Roles.WITHDRAWER_ROLE) {
    address[] memory wrappedNativeToken = new address[](1);
    wrappedNativeToken[0] = address(s_wrappedNativeToken);

    (bool isAllowlisted,) = s_feeAggregator.areAssetsAllowlisted(wrappedNativeToken);

    if (isAllowlisted) {
      revert Errors.AssetAllowlisted(wrappedNativeToken[0]);
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
      revert Errors.FeeAggregatorNotUpdated();
    }
    if (!IERC165(newFeeAggregator).supportsInterface(type(IFeeAggregator).interfaceId)) {
      revert InvalidFeeAggregator(newFeeAggregator);
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
