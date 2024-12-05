// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {LinkReceiver} from "src/LinkReceiver.sol";
import {NativeTokenReceiver} from "src/NativeTokenReceiver.sol";
import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";
import {EnumerableBytesSet} from "src/libraries/EnumerableBytesSet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {ILinkAvailable} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/automation/ILinkAvailable.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {ITypeAndVersion} from "@chainlink/contracts/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Contract which accrues assets and enables transferring out assets for swapping and further settlement to
/// swapper roles.
/// The contract enables opt-in support to receive assets from other chains via CCIP,
/// as well as bridge assets to other chains (to allowlisted receivers).
contract FeeAggregator is
  IFeeAggregator,
  EmergencyWithdrawer,
  LinkReceiver,
  ITypeAndVersion,
  ILinkAvailable,
  NativeTokenReceiver
{
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableBytesSet for EnumerableBytesSet.BytesSet;

  /// @notice This event is emitted when an asset is removed from the allowlist
  /// @param asset The address of the asset that was removed from the allowlist
  event AssetRemovedFromAllowlist(address asset);
  /// @notice This event is emitted when an asset is added to the allow list
  /// @param asset The address of the asset that was added to the allow list
  event AssetAddedToAllowlist(address asset);
  /// @notice This event is emitted when the CCIP Router Client address is set
  /// @param ccipRouter The address of the CCIP Router Client
  event CCIPRouterClientSet(address indexed ccipRouter);
  /// @notice This event is emitted when a destination chain is added to the allowlist
  /// @param chainSelector The selector of the destination chain that was added to the allowlist
  event DestinationChainAddedToAllowlist(uint64 chainSelector);
  /// @notice This event is emitted when a destination chain is removed from the allowlist
  /// @param chainSelector The selector of the destination chain that was removed from the allowlist
  event DestinationChainRemovedFromAllowlist(uint64 chainSelector);
  /// @notice This event is emitted when a receiver is added to the allowlist
  /// @param chainSelector The destination chain selector
  /// @param receiver The encoded address of the receiver that was added
  event ReceiverAddedToAllowlist(uint64 indexed chainSelector, bytes receiver);
  /// @notice This event is emitted when a receiver is removed from the allowlist
  /// @param chainSelector The destination chain selector
  /// @param receiver The encoded address of the receiver that was removed
  event ReceiverRemovedFromAllowlist(uint64 indexed chainSelector, bytes receiver);
  /// @notice This event is emitted when an asset is transferred for swapping
  /// @param to The address to which the asset was sent
  /// @param asset The address of the asset that was transferred
  /// @param amount The amount of asset that was transferred
  event AssetTransferredForSwap(address indexed to, address indexed asset, uint256 amount);
  /// @notice This event is emitted when a non allowlisted asset is withdrawn
  /// @param to The address that received the withdrawn asset
  /// @param asset The address of the asset that was withdrawn - address(0) is used for native token
  /// @param amount The amount of assets that was withdrawn
  event NonAllowlistedAssetWithdrawn(address indexed to, address indexed asset, uint256 amount);
  /// @notice This event is emitted when a bridgeAssets call is successfully initiated
  /// @param messageId CCIP Message ID
  /// @param message Message contents
  event BridgeAssetsMessageSent(bytes32 indexed messageId, Client.EVM2AnyMessage message);

  /// @notice This error is thrown when the contract's balance is not
  /// enough to pay bridging fees
  /// @param currentBalance The contract's balance in juels
  /// @param fee The minimum amount of juels required to bridge assets
  error InsufficientBalance(uint256 currentBalance, uint256 fee);
  /// @notice This error is thrown when an asset is being allow listed while
  /// already allow listed
  /// @param asset The asset that is already allowlisted
  error AssetAlreadyAllowlisted(address asset);
  /// @notice This error is thrown when attempting to remove a receiver that is
  /// not on the allowlist
  /// @param receiver The receiver that was not allowlisted
  /// @param chainSelector The destination chain selector that the receiver was not allowlisted for
  error ReceiverNotAllowlisted(uint64 chainSelector, bytes receiver);
  /// @notice This error is thrown when a receiver being added to the allowlist is already in the
  /// allowlist
  /// @param receiver The receiver that was already allowlisted
  /// @param chainSelector The destination chain selector that the receiver was already allowlisted for
  error ReceiverAlreadyAllowlisted(uint64 chainSelector, bytes receiver);
  /// @notice This error is thrown when attempting to add a 0 destination or source chain selector
  error InvalidChainSelector();

  /// @notice Parameters to instantiate the contract in the constructor
  // solhint-disable-next-line gas-struct-packing
  struct ConstructorParams {
    address admin; // ──────────────────╮ The initial contract admin
    uint48 adminRoleTransferDelay; // ──╯ The min seconds before the admin address can be transferred
    address linkToken; // The LINK token
    address ccipRouterClient; // The CCIP Router client
    address wrappedNativeToken; // The wrapped native token
  }

  /// @notice This struct contains the parameters to allowlist remote receivers on a given chain
  struct AllowlistedReceivers {
    uint64 remoteChainSelector; // ──╮ The remote chain selector to allowlist
    bytes[] receivers; // ───────────╯ The list of encoded remote receivers
  }

  /// @inheritdoc ITypeAndVersion
  string public constant override typeAndVersion = "Fee Aggregator 1.0.0";

  /// @dev Hash of encoded address(0) used for empty bytes32 address checks
  bytes32 internal constant EMPTY_ENCODED_BYTES32_ADDRESS_HASH = keccak256(abi.encode(address(0)));

  /// @notice CCIP Router client
  IRouterClient internal immutable i_ccipRouter;

  /// @notice The set of assets that are allowed to be bridged
  EnumerableSet.AddressSet internal s_allowlistedAssets;
  /// @notice The set of destination chain selectors that are allowed to receiver assets to the contract
  EnumerableSet.UintSet private s_allowlistedDestinationChains;

  /// @notice Mapping of chain selectors to the set of encoded addresses that are allowed to receive assets
  /// @dev We use bytes to store the addresses because CCIP transmits addresses as raw bytes.
  mapping(uint64 => EnumerableBytesSet.BytesSet) private s_allowlistedReceivers;

  constructor(
    ConstructorParams memory params
  )
    EmergencyWithdrawer(params.adminRoleTransferDelay, params.admin)
    LinkReceiver(params.linkToken)
    NativeTokenReceiver(params.wrappedNativeToken)
  {
    if (params.ccipRouterClient == address(0)) {
      revert Errors.InvalidZeroAddress();
    }

    i_ccipRouter = IRouterClient(params.ccipRouterClient);
    emit CCIPRouterClientSet(params.ccipRouterClient);
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 interfaceId
  ) public view override(PausableWithAccessControl) returns (bool) {
    return interfaceId == type(IFeeAggregator).interfaceId || PausableWithAccessControl.supportsInterface(interfaceId);
  }

  // ================================================================
  // │                     Receive & Swap Assets                    │
  // ================================================================

  /// @inheritdoc IFeeAggregator
  /// @dev precondition The caller must have the SWAPPER_ROLE
  /// @dev precondition The assets must be allowlisted
  /// @dev precondition The amounts must be greater than 0
  function transferForSwap(
    address to,
    address[] calldata assets,
    uint256[] calldata amounts
  ) external whenNotPaused onlyRole(Roles.SWAPPER_ROLE) {
    _validateAssetTransferInputs(assets, amounts);

    for (uint256 i; i < assets.length; ++i) {
      if (!s_allowlistedAssets.contains(assets[i])) {
        revert Errors.AssetNotAllowlisted(assets[i]);
      }

      address asset = assets[i];
      uint256 amount = amounts[i];

      _transferAsset(to, asset, amount);
      emit AssetTransferredForSwap(to, asset, amount);
    }
  }

  /// @inheritdoc IFeeAggregator
  function areAssetsAllowlisted(
    address[] calldata assets
  ) external view returns (bool areAllAssetsAllowlisted, address nonAllowlistedAsset) {
    for (uint256 i; i < assets.length; ++i) {
      if (!s_allowlistedAssets.contains(assets[i])) {
        return (false, assets[i]);
      }
    }
    return (true, address(0));
  }

  /// @notice Getter function to retrieve the list of allowlisted assets
  /// @return allowlistedAssets List of allowlisted assets
  function getAllowlistedAssets() external view returns (address[] memory allowlistedAssets) {
    return s_allowlistedAssets.values();
  }

  /// @notice Getter function to retrieve the list of allowlisted destination chains
  /// @return allowlistedDestinationChains List of allowlisted destination chains
  function getAllowlistedDestinationChains() external view returns (uint256[] memory allowlistedDestinationChains) {
    return s_allowlistedDestinationChains.values();
  }

  // ================================================================
  // │                           Bridging                           │
  // ================================================================

  /// @notice Bridges assets from the source chain to a receiving
  /// address on the destination chain
  /// @dev precondition The caller must have the BRIDGER_ROLE
  /// @dev precondition The contract must not be paused
  /// @dev precondition The contract must have sufficient LINK to pay
  /// the bridging fee
  /// @param bridgeAssetAmounts The amount of assets to bridge
  /// @param destinationChainSelector The chain to receive funds
  /// @param bridgeReceiver The address to receive funds
  /// @param extraArgs Extra arguments to pass to the CCIP
  /// @return messageId The bridging message ID
  function bridgeAssets(
    Client.EVMTokenAmount[] calldata bridgeAssetAmounts,
    uint64 destinationChainSelector,
    bytes calldata bridgeReceiver,
    bytes calldata extraArgs
  ) external whenNotPaused onlyRole(Roles.BRIDGER_ROLE) returns (bytes32 messageId) {
    if (!s_allowlistedReceivers[destinationChainSelector].contains(bridgeReceiver)) {
      revert ReceiverNotAllowlisted(destinationChainSelector, bridgeReceiver);
    }

    if (bridgeAssetAmounts.length == 0) {
      revert Errors.EmptyList();
    }

    // coverage:ignore-next
    Client.EVM2AnyMessage memory evm2AnyMessage =
      _buildBridgeAssetsMessage(bridgeAssetAmounts, bridgeReceiver, extraArgs);

    uint256 fees = i_ccipRouter.getFee(destinationChainSelector, evm2AnyMessage);

    uint256 currentBalance = i_linkToken.balanceOf(address(this));

    if (fees > currentBalance) {
      revert InsufficientBalance(currentBalance, fees);
    }

    IERC20(address(i_linkToken)).safeIncreaseAllowance(address(i_ccipRouter), fees);

    messageId = i_ccipRouter.ccipSend(destinationChainSelector, evm2AnyMessage);
    emit BridgeAssetsMessageSent(messageId, evm2AnyMessage);

    return messageId;
  }

  /// @notice Builds the CCIP message to bridge assets from the source chain
  /// to the destination chain
  /// @param bridgeAssetAmounts The assets to bridge and their amounts
  /// @param bridgeReceiver The address to receive bridged funds
  /// @param extraArgs Extra arguments to pass to the CCIP
  /// @return message The constructed CCIP message
  function _buildBridgeAssetsMessage(
    Client.EVMTokenAmount[] memory bridgeAssetAmounts,
    bytes memory bridgeReceiver,
    bytes calldata extraArgs
  ) internal returns (Client.EVM2AnyMessage memory message) {
    for (uint256 i; i < bridgeAssetAmounts.length; ++i) {
      address asset = bridgeAssetAmounts[i].token;
      if (!s_allowlistedAssets.contains(asset)) {
        revert Errors.AssetNotAllowlisted(asset);
      }

      IERC20(asset).safeIncreaseAllowance(address(i_ccipRouter), bridgeAssetAmounts[i].amount);
    }

    return Client.EVM2AnyMessage({
      receiver: bridgeReceiver,
      data: "",
      tokenAmounts: bridgeAssetAmounts,
      extraArgs: extraArgs,
      feeToken: address(i_linkToken)
    });
  }

  /// @notice Getter function to retrieve the list of allowlisted receivers for a chain
  /// @param destChainSelector The destination chain selector
  /// @return allowlistedReceivers List of encoded receiver addresses
  function getAllowlistedReceivers(
    uint64 destChainSelector
  ) external view returns (bytes[] memory allowlistedReceivers) {
    return s_allowlistedReceivers[destChainSelector].values();
  }

  /// @inheritdoc ILinkAvailable
  function linkAvailableForPayment() external view returns (int256 linkBalance) {
    // LINK balance is returned as an int256 to match the interface
    // It will never be negative and will always fit in an int256 since the max
    // supply of LINK is 1e27
    return int256(i_linkToken.balanceOf(address(this)));
  }

  /// @notice Return the current router
  /// @return ccipRouter CCIP router address
  function getRouter() public view returns (address ccipRouter) {
    return address(i_ccipRouter);
  }

  // ================================================================
  // │                   Asset administration                       │
  // ================================================================

  /// @notice Adds and removes assets from the allowlist
  /// @dev precondition The caller must have the ASSET_ADMIN_ROLE
  /// @dev precondition The contract must not be paused
  /// @dev precondition The assets to add must not be the zero address
  /// @dev precondition The assets to remove must be already allowlisted
  /// @dev precondition The assets to add must not already be allowlisted
  /// @param assetsToRemove The list of assets to remove from the allowlist
  /// @param assetsToAdd The list of assets to add to the allowlist
  function applyAllowlistedAssetUpdates(
    address[] calldata assetsToRemove,
    address[] calldata assetsToAdd
  ) external onlyRole(Roles.ASSET_ADMIN_ROLE) whenNotPaused {
    for (uint256 i; i < assetsToRemove.length; ++i) {
      address asset = assetsToRemove[i];
      if (!s_allowlistedAssets.remove(asset)) {
        revert Errors.AssetNotAllowlisted(asset);
      }
      emit AssetRemovedFromAllowlist(asset);
    }

    for (uint256 i; i < assetsToAdd.length; ++i) {
      address asset = assetsToAdd[i];
      if (asset == address(0)) {
        revert Errors.InvalidZeroAddress();
      }
      if (!s_allowlistedAssets.add(asset)) {
        revert AssetAlreadyAllowlisted(asset);
      }
      emit AssetAddedToAllowlist(asset);
    }
  }

  /// @notice Withdraws non allowlisted assets from the contract
  /// @dev precondition The caller must have the WITHDRAWER_ROLE
  /// @dev precondition The list of WithdrawAssetAmount must not be empty
  /// @dev precondition The asset must not be the zero address
  /// @dev precondition The amount must be greater than 0
  /// @dev precondition The asset must not be allowlisted
  /// @param to The address to transfer the assets to
  /// @param assets The list of assets to withdraw
  /// @param amounts The list of asset amounts to withdraw
  function withdrawNonAllowlistedAssets(
    address to,
    address[] calldata assets,
    uint256[] calldata amounts
  ) external onlyRole(Roles.WITHDRAWER_ROLE) {
    _validateAssetTransferInputs(assets, amounts);

    for (uint256 i; i < assets.length; ++i) {
      address asset = assets[i];
      uint256 amount = amounts[i];

      if (s_allowlistedAssets.contains(asset)) {
        revert Errors.AssetAllowlisted(asset);
      }

      _transferAsset(to, asset, amount);
      emit NonAllowlistedAssetWithdrawn(to, asset, amount);
    }
  }

  /// @notice Withdraws native tokens from the contract to the specified address
  /// @dev precondition The caller must have the WITHDRAWER_ROLE
  /// @dev precondition The wrapped native token must not be allowlisted
  /// @param to The address to transfer the native tokens to
  /// @param amount The amount of native tokens to transfer
  function withdrawNative(address payable to, uint256 amount) external onlyRole(Roles.WITHDRAWER_ROLE) {
    address wrappedNativeToken = address(s_wrappedNativeToken);

    if (s_allowlistedAssets.contains(wrappedNativeToken)) {
      revert Errors.AssetAllowlisted(wrappedNativeToken);
    }

    _transferNative(to, amount);
    emit NonAllowlistedAssetWithdrawn(to, address(0), amount);
  }

  /// @notice Adds and removes receivers from the allowlist for specified chains
  /// @dev The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The contract must not be paused
  /// @param receiversToRemove The list of receivers to remove from the allowlist
  /// @param receiversToAdd The list of receivers to add to the allowlist
  function applyAllowlistedReceiverUpdates(
    AllowlistedReceivers[] calldata receiversToRemove,
    AllowlistedReceivers[] calldata receiversToAdd
  ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
    for (uint256 i; i < receiversToRemove.length; ++i) {
      uint64 destChainSelector = receiversToRemove[i].remoteChainSelector;
      bytes[] memory receivers = receiversToRemove[i].receivers;

      for (uint256 j; j < receivers.length; ++j) {
        bytes memory receiver = receivers[j];
        if (!s_allowlistedReceivers[destChainSelector].remove(receiver)) {
          revert ReceiverNotAllowlisted(destChainSelector, receiver);
        }
        emit ReceiverRemovedFromAllowlist(destChainSelector, receiver);
      }

      if (s_allowlistedReceivers[destChainSelector].length() == 0) {
        s_allowlistedDestinationChains.remove(destChainSelector);
        emit DestinationChainRemovedFromAllowlist(destChainSelector);
      }
    }

    // Process additions next
    for (uint256 i; i < receiversToAdd.length; ++i) {
      uint64 destChainSelector = receiversToAdd[i].remoteChainSelector;
      if (destChainSelector == 0) {
        revert InvalidChainSelector();
      }

      bytes[] memory receivers = receiversToAdd[i].receivers;

      for (uint256 j; j < receivers.length; ++j) {
        bytes memory receiver = receivers[j];
        if (receiver.length == 0 || keccak256(receiver) == EMPTY_ENCODED_BYTES32_ADDRESS_HASH) {
          revert Errors.InvalidZeroAddress();
        }

        if (!s_allowlistedReceivers[destChainSelector].add(receiver)) {
          revert ReceiverAlreadyAllowlisted(destChainSelector, receiver);
        }
        emit ReceiverAddedToAllowlist(destChainSelector, receiver);
      }

      if (s_allowlistedDestinationChains.add(destChainSelector)) {
        emit DestinationChainAddedToAllowlist(destChainSelector);
      }
    }
  }

  /// @dev Sets the wrapped native token.
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @param wrappedNativeToken The wrapped native token address.
  function setWrappedNativeToken(
    address wrappedNativeToken
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setWrappedNativeToken(wrappedNativeToken);
  }
}
