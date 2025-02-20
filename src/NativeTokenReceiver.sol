// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IWERC20} from "@chainlink/contracts/src/v0.8/shared/interfaces/IWERC20.sol";
import {Errors} from "src/libraries/Errors.sol";

/// @notice Native token reciever contract that handles native token wrapping.
abstract contract NativeTokenReceiver {
  /// @notice This event is emitted when the wrapped native token is set.
  /// @param wrappedNativeToken The wrapped native token address.
  event WrappedNativeTokenSet(address wrappedNativeToken);

  /// @notice This error is thrown when trying to wrap native tokens without any outstanding balance.
  error ZeroBalance();

  /// @notice The minimum gas left in the call to perform a wrapping call on receive.
  uint256 public constant MIN_GAS_FOR_RECEIVE = 2300;

  /// @notice The wrapped native token.
  IWERC20 internal s_wrappedNativeToken;

  constructor(
    address wrappedNativeToken
  ) {
    if (wrappedNativeToken != address(0)) {
      _setWrappedNativeToken(wrappedNativeToken);
    }
  }

  // ================================================================
  // |                    Native Token Handling                     |
  // ================================================================

  /// @notice Wraps the outstanding native token balance.
  function deposit() external virtual {
    if (address(this).balance == 0) {
      revert ZeroBalance();
    }

    s_wrappedNativeToken.deposit{value: address(this).balance}();
  }

  /// @dev Receive function that autowraps native tokens on receive if the gas left is greater than 2300 which
  /// indicates a low level call. Otherwise, transfer method has been used which won't allow for a wrapping call so the
  /// contracts simply receives the msg.value.
  receive() external payable {
    if (gasleft() > MIN_GAS_FOR_RECEIVE) {
      if (address(s_wrappedNativeToken) != address(0)) {
        // We try catch the deposit call as some chain's wrapped native token may not support the deposit function
        try s_wrappedNativeToken.deposit{value: msg.value}() {} catch {}
      }
    }
  }

  // ================================================================
  // |                            Config                            |
  // ================================================================

  /// @dev Sets the wrapped native token.
  /// @dev We allow setting to the zero address for chains that may not have a wrapped native token.
  /// @param wrappedNativeToken The wrapped native token address.
  function _setWrappedNativeToken(
    address wrappedNativeToken
  ) internal {
    if (wrappedNativeToken == address(s_wrappedNativeToken)) {
      revert Errors.ValueNotUpdated();
    }

    s_wrappedNativeToken = IWERC20(wrappedNativeToken);

    emit WrappedNativeTokenSet(wrappedNativeToken);
  }

  /// @notice Getter function to retrieve the configured wrapped native token.
  /// @return wrappedNativeToken The configured wrapped native token.
  function getWrappedNativeToken() external view returns (IWERC20 wrappedNativeToken) {
    return s_wrappedNativeToken;
  }
}
