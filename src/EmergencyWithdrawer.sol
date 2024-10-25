// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Errors} from "src/libraries/Errors.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Base contract that adds ERC20 emergencyWithdraw functionality.
abstract contract EmergencyWithdrawer is PausableWithAccessControl {
  using SafeERC20 for IERC20;

  /// @notice This event is emitted when an asset is transferred
  /// @notice to the specified address
  /// @param asset The address of the  asset that was transferred
  /// @param amount The amount of asset that was transferred
  event AssetTransferred(address indexed to, address indexed asset, uint256 amount);

  constructor(uint48 adminRoleTransferDelay, address admin) PausableWithAccessControl(adminRoleTransferDelay, admin) {}

  /// @notice Withdraws assets from the contract to the specfied address
  /// @dev precondition The contract must be paused
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @param to The address to transfer the assets to
  /// @param assets The list of assets to transfer
  /// @param amounts The list of asset amounts to transfer
  function emergencyWithdraw(
    address to,
    address[] calldata assets,
    uint256[] calldata amounts
  ) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
    _validateAssetTransferInputs(assets, amounts);

    for (uint256 i = 0; i < assets.length; i++) {
      _transferAsset(to, assets[i], amounts[i]);
    }
  }

  /// @dev Helper function to validate the asset transfer inputs
  /// @dev precondition The asset list must not be empty
  /// @dev precondition The asset list and the amount list must have the same length
  function _validateAssetTransferInputs(address[] calldata assets, uint256[] calldata amounts) internal pure {
    if (assets.length == 0) {
      revert Errors.EmptyList();
    }
    if (assets.length != amounts.length) {
      revert Errors.ArrayLengthMismatch();
    }
  }

  /// @dev Helper function to transfer a list of assets
  /// @dev precondition The asset list must not be empty
  /// @dev precondition The asset list and the amount list must have the same length
  /// @dev precondition The transferred assets must not be the zero address
  /// @dev precondition The amounts must be greater than zero
  /// @param to The address to transfer the asset to
  /// @param asset The asset to transfer
  /// @param amount The amount of asset to transfer
  function _transferAsset(address to, address asset, uint256 amount) internal {
    if (asset == address(0)) {
      revert Errors.InvalidZeroAddress();
    }
    if (amount == 0) {
      revert Errors.InvalidZeroAmount();
    }

    IERC20(asset).safeTransfer(to, amount);

    emit AssetTransferred(to, asset, amount);
  }
}
