// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Errors} from "src/libraries/Errors.sol";

import {IERC677Receiver} from "@chainlink/contracts/src/v0.8/shared/token/ERC677/IERC677Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @notice Base contract that adds ERC677 transferAndCall receiver functionality scoped to the LINK token
abstract contract LinkReceiver is IERC677Receiver {
  /// @notice This event is emitted when the LINK token address is set
  /// @param linkToken The LINK token address
  event LinkTokenSet(address indexed linkToken);

  /// @notice This error is thrown when the sender is not the LINK token
  error SenderNotLinkToken();

  /// @notice The link token
  IERC20 internal immutable i_linkToken;

  constructor(
    address linkToken
  ) {
    if (linkToken == address(0)) {
      revert Errors.InvalidZeroAddress();
    }

    i_linkToken = IERC20(linkToken);
    emit LinkTokenSet(linkToken);
  }

  // ================================================================
  // │                            LINK Token                        │
  // ================================================================

  /// @inheritdoc IERC677Receiver
  /// @dev Implementing onTokenTransfer only to maximize Link receiving compatibility. No extra logic added.
  /// @dev precondition The sender must be the LINK token
  function onTokenTransfer(address, uint256, bytes calldata) external view {
    if (msg.sender != address(i_linkToken)) revert SenderNotLinkToken();
  }

  /// @notice Getter function to retrieve the LINK token address
  /// @return linkToken The LINK token address
  function getLinkToken() external view returns (IERC20 linkToken) {
    return i_linkToken;
  }
}
