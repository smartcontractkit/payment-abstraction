// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Common} from "src/libraries/Common.sol";

/// @notice Interface for FeeAggregator contracts, which accrue assets, and allow transferring out allowlisted assets.
interface IFeeAggregator {
  /// @notice Transfers a list of allowlisted assets to the target recipient. Can only be called by addresses with the
  /// SWAPPER role.
  /// @param to The address to transfer the assets to
  /// @param assetAmounts List of assets and amounts to transfer
  function transferForSwap(address to, Common.AssetAmount[] calldata assetAmounts) external;

  /// @notice Getter function to retrieve the list of allowlisted assets
  /// @return allowlistedAssets List of allowlisted assets
  function getAllowlistedAssets() external view returns (address[] memory allowlistedAssets);

  /// @notice Checks if an asset is in the allow list
  /// @param asset The asset to check
  /// @return isAllowlisted Returns true if asset is in the allow list, false if not
  function isAssetAllowlisted(
    address asset
  ) external view returns (bool isAllowlisted);
}
