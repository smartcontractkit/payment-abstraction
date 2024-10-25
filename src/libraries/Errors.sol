// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

library Errors {
  /// @notice This error is thrown whenever a zero-address is supplied when
  /// a non-zero address is required
  error InvalidZeroAddress();
  /// @notice This error is thrown when trying to pass in an empty list as an argument
  error EmptyList();
  /// @notice This error is thrown when an asset is being allow listed while
  /// already allow listed
  /// @param asset The asset that is already allowlisted
  error AssetAlreadyAllowlisted(address asset);
  /// @notice This error is thrown when attempting to remove an asset that is
  /// not on the allowlist
  /// @param asset The asset that is not allowlisted
  error AssetNotAllowlisted(address asset);
  /// @notice This error is thrown when the asset list and the swap params list
  /// have different lengths
  error AssetsSwapParamsMismatch();
  /// @notice This error is thrown when the contract's balance is not
  /// enough to pay bridging fees
  /// @param currentBalance The contract's balance in juels
  /// @param fee The minimum amount of juels required to bridge assets
  error InsufficientBalance(uint256 currentBalance, uint256 fee);
  /// @notice This error is thrown when a sender being added to the allowlist is already in the
  /// allowlist
  /// @param sender The sender that was already allowlisted
  /// @param chainSelector The source chain selector that the sender was already allowlisted for
  error SenderAlreadyAllowlisted(uint64 chainSelector, bytes sender);
  /// @notice This error is thrown when attempting to remove a sender that is
  /// not on the allowlist
  /// @param sender The sender that was not allowlisted
  /// @param chainSelector The source chain selector that the sender was not allowlisted for
  error SenderNotAllowlisted(uint64 chainSelector, bytes sender);
  /// @notice This error is thrown when trying to set an empty swap path
  error EmptySwapPath();
  /// @notice This error is thrown when the fee aggregator is not
  /// updated
  error FeeAggregatorNotUpdated();
  /// @notice This error is thrown when the forwarder address is not updated
  error ForwarderNotUpdated();
  /// @notice This error is thrown when max slippage parameter set is 0
  error InvalidSlippage();
  /// @notice This error is thrown when the swap path is invalid as compared to the swap path set by
  /// the Admin.
  error InvalidSwapPath();
  /// @notice This error is thrown when the recipent of the swap pram does not match the receiver's
  /// fee recipent address.
  error FeeRecipientMismatch();
  /// @notice This error is thrown when the data returned by the oracle is zero
  error ZeroOracleData();
  /// @notice This error is thrown when the data returned by the oracle is older than the set
  /// threshold
  error StaleOracleData();
  /// @notice This error is thrown when trying to set the same LINK receiver as the one already set
  error LINKReceiverNotUpdated();
  /// @notice This error is thrown when an unauthorized caller tries to call a function
  /// another address than that caller
  error AccessForbidden();
  /// @notice This error is thrown when the amount received from a swap is less than the minimum
  /// amount expected
  error InsufficientAmountReceived();
  /// @notice This error is thrown when passing in a zero amount as a function parameter
  error InvalidZeroAmount();
  /// @notice This error is thrown when all performed swaps have failed
  error AllSwapsFailed();
  /// @notice This error is thrown trying to set the same deadline delay as the one already set
  error DeadlineDelayNotUpdated();
  /// @notice This error is thrown when trying to set the deadline delay to a value lower than the
  /// minimum threshold
  error DeadlineDelayTooLow(uint96 deadlineDelay, uint96 minDeadlineDelay);
  /// @notice This error is thrown when trying to set the deadline delay to a value higher than the
  /// maximum threshold
  error DeadlineDelayTooHigh(uint96 deadlineDelay, uint96 maxDeadlineDelay);
  /// @notice This error is thrown when the transaction timestamp is greater than the deadline
  error TransactionTooOld(uint256 timestamp, uint256 deadline);
  /// @notice This error is thrown when trying to withdraw an asset that is allowlisted
  error AssetAllowlisted(address asset);
  /// @notice This error is thrown when the sender is not the LINK token
  error SenderNotLinkToken();
  /// @notice This error is thrown when attempting to remove a receiver that is
  /// not on the allowlist
  /// @param receiver The receiver that was not allowlisted
  /// @param chainSelector The source chain selector that the receiver was not allowlisted for
  error ReceiverNotAllowlisted(uint64 chainSelector, bytes receiver);
  /// @notice This error is thrown when a receiver being added to the allowlist is already in the
  /// allowlist
  /// @param receiver The receiver that was already allowlisted
  /// @param chainSelector The source chain selector that the receiver was already allowlisted for
  error ReceiverAlreadyAllowlisted(uint64 chainSelector, bytes receiver);
  /// @notice This error is thrown when two arrays have different lengths
  error ArrayLengthMismatch();
}
