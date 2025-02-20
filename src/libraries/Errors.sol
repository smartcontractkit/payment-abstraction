// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/// @notice Library for common custom errors used across multiple contracts
library Errors {
  /// @notice This error is thrown whenever a zero-address is supplied when
  /// a non-zero address is required
  error InvalidZeroAddress();
  /// @notice This error is thrown when trying to pass in an empty list as an argument
  error EmptyList();
  /// @notice This error is thrown when the data returned by the price feed is zero
  error ZeroFeedData();
  /// @notice This error is thrown when the data returned by the price feed is older than the set
  /// threshold
  error StaleFeedData();
  /// @notice This error is thrown when an unauthorized caller tries to call a function
  /// another address than that caller
  error AccessForbidden();
  /// @notice This error is thrown when passing in a zero amount as a function parameter
  error InvalidZeroAmount();
  /// @notice This error is thrown when attempting to remove an asset that is
  /// not on the allowlist
  /// @param asset The asset that is not allowlisted
  error AssetNotAllowlisted(address asset);
  /// @notice This error is thrown when trying to withdraw an asset that is allowlisted
  error AssetAllowlisted(address asset);
  /// @notice This error is thrown when a value is not updated e.g. when trying to configure a state variable the same
  /// value as the one already configured
  error ValueNotUpdated();
  /// @notice This error is thrown when setting a fee aggregator that does not support the IFeeAggregator interface
  error InvalidFeeAggregator(address feeAggregator);
}
