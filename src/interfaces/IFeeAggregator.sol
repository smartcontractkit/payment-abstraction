// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IFeeAggregator {
  /// @notice Transfers a list of allowlisted assets to the target recipient. Can only be called by addresses with the
  /// SWAPPER role.
  /// @param to The address to transfer the assets to
  /// @param assets List of assets to transfer
  /// @param amounts List of asset amounts to transfer
  function transferForSwap(address to, address[] calldata assets, uint256[] calldata amounts) external;

  /// @notice Getter function to retrieve the list of allowlisted assets
  /// @return address[] List of allowlisted assets
  function getAllowlistedAssets() external view returns (address[] memory);

  /// @notice Checks if a list of assets are in the allow list
  /// @param assets The list of assets to check
  /// @return bool Returns true if all assets are in the allow list, false if not
  /// @return address The address of the asset that is not in the allow list
  function areAssetsAllowlisted(
    address[] calldata assets
  ) external view returns (bool, address);
}
