// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from
  "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {IFeeAggregator} from "src/interfaces/IFeeAggregator.sol";
import {EnumerableBytesSet} from "src/libraries/EnumerableBytesSet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {ILinkAvailable} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/automation/ILinkAvailable.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {ITypeAndVersion} from "@chainlink/contracts/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract FeeAggregator is IFeeAggregator, EmergencyWithdrawer, ITypeAndVersion, ILinkAvailable, CCIPReceiver {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableBytesSet for EnumerableBytesSet.BytesSet;

  /// @notice This event is emitted when the LINK token address is set
  /// @param linkToken The LINK token address
  event LinkTokenSet(address indexed linkToken);
  /// @notice This event is emitted when an asset is removed from the allowlist
  /// @param asset The address of the asset that was removed from the allowlist
  event AssetRemovedFromAllowlist(address asset);
  /// @notice This event is emitted when an asset is added to the allow list
  /// @param asset The address of the asset that was added to the allow list
  event AssetAddedToAllowlist(address asset);
  /// @notice This event is emitted when an asset is transferred
  /// @param asset The address of the  asset that was transferred
  /// @param amount The amount of asset that was transferred
  event AssetTransferred(address indexed asset, uint256 amount);
  /// @notice This event is emitted when the CCIP Router Client address is set
  /// @param ccipRouter The address of the CCIP Router Client
  event CCIPRouterClientSet(address indexed ccipRouter);
  /// @notice This event is emitted when a sender is added to the allow list
  /// @param sender The encoded address of the sender that was added to the allow list
  event SenderAddedToAllowlist(uint64 indexed chainSelector, bytes sender);
  /// @notice This event is emitted when a sender is removed from the allowlist
  /// @param sender The encoded address of the sender that was removed from the allowlist
  event SenderRemovedFromAllowlist(uint64 indexed chainSelector, bytes sender);
  /// @notice This event is emitted when a source chain sender is added to the allowlist
  /// @param chainSelector The selector of the source chain that was added to the allowlist
  event SourceChainAddedToAllowlist(uint64 chainSelector);
  /// @notice This event is emitted when a source chain is removed from the allowlist
  /// @param chainSelector The selector of the source chain that was removed from the allowlist
  event SourceChainRemovedFromAllowlist(uint64 chainSelector);
  /// @notice This event is emitted when a destination chain is added to the allowlist
  /// @param chainSelector The selector of the destination chain that was added to the allowlist
  event DestinationChainAddedToAllowlist(uint64 chainSelector);
  /// @notice This event is emitted when a destination chain is removed from the allowlist
  /// @param chainSelector The selector of the destination chain that was removed from the allowlist
  event DestinationChainRemovedFromAllowlist(uint64 chainSelector);
  /// @notice This event is emitted when an asset is bridged to the contract
  /// @param asset The address of the asset that was received
  /// @param amount The amount assets that was received
  event AssetReceived(address indexed asset, uint256 amount);
  /// @notice This event is emitted when a message is received from a source chain
  /// @param sender The address of the sender that bridged the asset
  /// @param chainSelector The selector of the source chain that the asset was bridged from
  /// @param messageId The unique identifier of the message that bridged the asset
  event MessageReceived(bytes indexed sender, uint256 indexed chainSelector, bytes32 messageId);
  /// @notice This event is emitted when a receiver is added to the allowlist
  /// @param chainSelector The destination chain selector
  /// @param receiver The encoded address of the receiver that was added
  event ReceiverAddedToAllowlist(uint64 indexed chainSelector, bytes receiver);
  /// @notice This event is emitted when a receiver is removed from the allowlist
  /// @param chainSelector The destination chain selector
  /// @param receiver The encoded address of the receiver that was removed
  event ReceiverRemovedFromAllowlist(uint64 indexed chainSelector, bytes receiver);

  /// @notice Parameters to instantiate the contract in the constructor
  struct ConstructorParams {
    address admin; // ───────────────────────────╮ The initial contract admin
    uint48 adminRoleTransferDelay; // ───────────╯ The min seconds before the admin address can be transferred
    address linkToken; //    The LINK token
    address ccipRouterClient; //    The CCIP Router client
  }

  /// @notice This struct contains the parameters to allowlist senders on a given chain
  struct AllowlistedSenders {
    uint64 sourceChainSelector; // ─╮ The source chain selector to allowlist the senders for
    bytes[] senders; // ────────────╯ The list of encoded sender addresses to be added to the allowlist
  }

  /// @notice This struct contains the parameters to allowlist senders on a given chain
  struct AllowlistedReceivers {
    uint64 destChainSelector; // ─╮ The destination chain selector to allowlist the senders for
    bytes[] receivers; // ────────╯ The list of encoded receiver addresses to be added to the allowlist
  }

  /// @inheritdoc ITypeAndVersion
  string public constant override typeAndVersion = "Fee Aggregator 1.0.0";

  /// @notice The link token
  LinkTokenInterface internal immutable i_linkToken;

  /// @notice The set of assets that are allowed to be bridged
  EnumerableSet.AddressSet internal s_allowlistedAssets;
  /// @notice The set of source chain selectors that are allowed to bridge assets to the contract
  EnumerableSet.UintSet private s_allowlistedSourceChains;
  /// @notice The set of destination chain selectors that are allowed to receiver assets to the contract
  EnumerableSet.UintSet private s_allowlistedDestinationChains;

  /// @notice Mapping of chain selectors to the set of encoded addresses that are allowed to bridge
  /// assets
  /// @dev We use bytes to store the addresses because CCIP transmits the sender's address as a
  /// raw bytes.
  mapping(uint64 chainSelector => EnumerableBytesSet.BytesSet allowlistedSenders) private s_allowlistedSenders;

  /// @notice Mapping of chain selectors to the set of encoded addresses that are allowed to receive assets
  /// @dev We use bytes to store the addresses because CCIP transmits addresses as raw bytes.
  mapping(uint64 => EnumerableBytesSet.BytesSet) private s_allowlistedReceivers;

  constructor(
    ConstructorParams memory params
  ) EmergencyWithdrawer(params.adminRoleTransferDelay, params.admin) CCIPReceiver(params.ccipRouterClient) {
    if (params.linkToken == address(0)) {
      revert Errors.InvalidZeroAddress();
    }

    i_linkToken = LinkTokenInterface(params.linkToken);
    emit LinkTokenSet(params.linkToken);
    emit CCIPRouterClientSet(params.ccipRouterClient);
  }

  // ================================================================
  // │                     Receive & Swap Assets                    │
  // ================================================================

  /// @inheritdoc CCIPReceiver
  /// @notice This function is executed upon assets being bridged to the contract through CCIP
  /// @dev precondition The sender must be allowlisted
  function _ccipReceive(
    Client.Any2EVMMessage memory message
  ) internal override {
    if (!s_allowlistedSenders[message.sourceChainSelector].contains(message.sender)) {
      revert Errors.SenderNotAllowlisted(message.sourceChainSelector, message.sender);
    }

    for (uint256 i; i < message.destTokenAmounts.length; ++i) {
      emit AssetReceived(message.destTokenAmounts[i].token, message.destTokenAmounts[i].amount);
    }

    emit MessageReceived(message.sender, message.sourceChainSelector, message.messageId);
  }

  /// @inheritdoc IFeeAggregator
  /// @dev precondition The caller must have the SWAPPER_ROLE
  /// @dev precondition The asset must be allowlisted
  /// @dev precondition The amount must be greater than 0
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

      _transferAsset(to, assets[i], amounts[i]);
    }
  }

  /// @inheritdoc IFeeAggregator
  function areAssetsAllowlisted(
    address[] calldata assets
  ) external view returns (bool, address) {
    for (uint256 i; i < assets.length; ++i) {
      if (!s_allowlistedAssets.contains(assets[i])) {
        return (false, assets[i]);
      }
    }
    return (true, address(0));
  }

  /// @notice Getter function to retrieve the list of allowlisted assets
  /// @return address[] List of allowlisted assets
  function getAllowlistedAssets() external view returns (address[] memory) {
    return s_allowlistedAssets.values();
  }

  /// @notice Getter function to retrieve the list of allowlisted senders
  /// @param chainSelector The selector of the source chain
  /// @return List of encoded sender addresses
  function getAllowlistedSenders(
    uint64 chainSelector
  ) external view returns (bytes[] memory) {
    return s_allowlistedSenders[chainSelector].values();
  }

  /// @notice Getter function to retrieve the list of allowlisted sender source chains
  /// @return List of allowlisted source chains
  function getAllowlistedSourceChains() external view returns (uint256[] memory) {
    return s_allowlistedSourceChains.values();
  }

  /// @notice Getter function to retrieve the list of allowlisted destination chains
  /// @return List of allowlisted destination chains
  function getAllowlistedDestinationChains() external view returns (uint256[] memory) {
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
  /// @param data Arbitrary data that can be sent along to the receiving
  /// address on the destination chain
  /// @param extraArgs Extra arguments to pass to the CCIP
  /// @return bytes32 The bridging message ID
  function bridgeAssets(
    Client.EVMTokenAmount[] calldata bridgeAssetAmounts,
    uint64 destinationChainSelector,
    bytes calldata bridgeReceiver,
    bytes calldata data,
    bytes calldata extraArgs
  ) external whenNotPaused onlyRole(Roles.BRIDGER_ROLE) returns (bytes32) {
    if (!s_allowlistedReceivers[destinationChainSelector].contains(bridgeReceiver)) {
      revert Errors.ReceiverNotAllowlisted(destinationChainSelector, bridgeReceiver);
    }

    // coverage:ignore-next
    Client.EVM2AnyMessage memory evm2AnyMessage =
      _buildBridgeAssetsMessage(bridgeAssetAmounts, bridgeReceiver, data, extraArgs);

    uint256 fees = IRouterClient(CCIPReceiver.getRouter()).getFee(destinationChainSelector, evm2AnyMessage);

    uint256 currentBalance = i_linkToken.balanceOf(address(this));

    if (fees > currentBalance) {
      revert Errors.InsufficientBalance(currentBalance, fees);
    }

    IERC20(address(i_linkToken)).safeIncreaseAllowance(CCIPReceiver.getRouter(), fees);

    return IRouterClient(CCIPReceiver.getRouter()).ccipSend(destinationChainSelector, evm2AnyMessage);
  }

  /// @notice Builds the CCIP message to bridge assets from the source chain
  /// to the destination chain
  /// @param bridgeAssetAmounts The assets to bridge and their amounts
  /// @param bridgeReceiver The address to receive bridged funds
  /// @param data Arbitrary data to be passed along to the receiver address
  /// on the destination chain
  /// @param extraArgs Extra arguments to pass to the CCIP
  function _buildBridgeAssetsMessage(
    Client.EVMTokenAmount[] memory bridgeAssetAmounts,
    bytes memory bridgeReceiver,
    bytes calldata data,
    bytes calldata extraArgs
  ) internal returns (Client.EVM2AnyMessage memory) {
    for (uint256 i; i < bridgeAssetAmounts.length; ++i) {
      address asset = bridgeAssetAmounts[i].token;
      if (!s_allowlistedAssets.contains(asset)) {
        revert Errors.AssetNotAllowlisted(asset);
      }

      IERC20(asset).safeIncreaseAllowance(CCIPReceiver.getRouter(), bridgeAssetAmounts[i].amount);
    }

    return Client.EVM2AnyMessage({
      receiver: bridgeReceiver,
      data: data,
      tokenAmounts: bridgeAssetAmounts,
      extraArgs: extraArgs,
      feeToken: address(i_linkToken)
    });
  }

  /// @notice Getter function to retrieve the list of allowlisted receivers for a chain
  /// @param destChainSelector The destination chain selector
  /// @return List of encoded receiver addresses
  function getAllowlistedReceivers(
    uint64 destChainSelector
  ) external view returns (bytes[] memory) {
    return s_allowlistedReceivers[destChainSelector].values();
  }

  /// @inheritdoc ILinkAvailable
  function linkAvailableForPayment() external view returns (int256 linkBalance) {
    // LINK balance is returned as an int256 to match the interface
    // It will never be negative and will always fit in an int256 since the max
    // supply of LINK is 1e27
    return int256(i_linkToken.balanceOf(address(this)));
  }

  // ================================================================
  // │                    Administrative                            │
  // ================================================================

  /// @notice Adds and removes assets from the allowlist
  /// @dev precondition The caller must have the ASSET_ADMIN_ROLE
  /// @dev precondition The contract must not be paused
  /// @dev precondition The assets to add must not be the zero address
  /// @dev precondition The assets to remove must be already allowlisted
  /// @dev precondition The assets to add must not already be allowlisted
  /// @param assetsToRemove The list of assets to remove from the allowlist
  /// @param assetsToAdd The list of assets to add to the allowlist
  function applyAllowlistedAssets(
    address[] calldata assetsToRemove,
    address[] calldata assetsToAdd
  ) external onlyRole(Roles.ASSET_ADMIN_ROLE) whenNotPaused {
    for (uint256 i; i < assetsToRemove.length; ++i) {
      address asset = assetsToRemove[i];
      if (!s_allowlistedAssets.contains(asset)) {
        revert Errors.AssetNotAllowlisted(asset);
      }
      s_allowlistedAssets.remove(asset);
      emit AssetRemovedFromAllowlist(asset);
    }

    for (uint256 i; i < assetsToAdd.length; ++i) {
      address asset = assetsToAdd[i];
      if (asset == address(0)) {
        revert Errors.InvalidZeroAddress();
      }
      if (!s_allowlistedAssets.add(asset)) {
        revert Errors.AssetAlreadyAllowlisted(asset);
      }
      emit AssetAddedToAllowlist(asset);
    }
  }

  /// @notice Withdraws non allowlisted assets from the contract
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
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
    }
  }

  /// @notice Adds and removes senders from the allowlist
  /// @dev precondition The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The contract must not be paused
  /// @dev precondition The senders to add must not be already allowlisted
  /// @dev precondition The senders to remove must be already allowlisted
  /// @param sendersToRemove The list of senders to remove from the allowlist
  /// @param sendersToAdd The list of senders to add to the allowlist
  function applyAllowlistedSenders(
    AllowlistedSenders[] calldata sendersToRemove,
    AllowlistedSenders[] calldata sendersToAdd
  ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
    for (uint256 i; i < sendersToRemove.length; ++i) {
      uint64 sourceChainSelector = sendersToRemove[i].sourceChainSelector;
      bytes[] memory senders = sendersToRemove[i].senders;

      for (uint256 j; j < senders.length; ++j) {
        bytes memory sender = senders[j];
        if (!s_allowlistedSenders[sourceChainSelector].contains(sender)) {
          revert Errors.SenderNotAllowlisted(sourceChainSelector, sender);
        }
        s_allowlistedSenders[sourceChainSelector].remove(sender);
        emit SenderRemovedFromAllowlist(sourceChainSelector, sender);
      }

      if (s_allowlistedSenders[sourceChainSelector].length() == 0) {
        s_allowlistedSourceChains.remove(sourceChainSelector);
        emit SourceChainRemovedFromAllowlist(sourceChainSelector);
      }
    }

    for (uint256 i; i < sendersToAdd.length; ++i) {
      uint64 sourceChainSelector = sendersToAdd[i].sourceChainSelector;
      bytes[] memory senders = sendersToAdd[i].senders;

      for (uint256 j; j < senders.length; ++j) {
        bytes memory sender = senders[j];
        if (s_allowlistedSenders[sourceChainSelector].contains(sender)) {
          revert Errors.SenderAlreadyAllowlisted(sourceChainSelector, sender);
        }
        s_allowlistedSenders[sourceChainSelector].add(sender);
        emit SenderAddedToAllowlist(sourceChainSelector, sender);
      }

      if (s_allowlistedSourceChains.add(sourceChainSelector)) {
        emit SourceChainAddedToAllowlist(sourceChainSelector);
      }
    }
  }

  /// @notice Adds and removes receivers from the allowlist for specified chains
  /// @dev The caller must have the DEFAULT_ADMIN_ROLE
  /// @dev precondition The contract must not be paused
  /// @param receiversToRemove The list of receivers to remove from the allowlist
  /// @param receiversToAdd The list of receivers to add to the allowlist
  function applyAllowlistedReceivers(
    AllowlistedReceivers[] calldata receiversToRemove,
    AllowlistedReceivers[] calldata receiversToAdd
  ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
    for (uint256 i; i < receiversToRemove.length; ++i) {
      uint64 destChainSelector = receiversToRemove[i].destChainSelector;
      bytes[] memory receivers = receiversToRemove[i].receivers;

      for (uint256 j; j < receivers.length; ++j) {
        bytes memory receiver = receivers[j];
        if (!s_allowlistedReceivers[destChainSelector].contains(receiver)) {
          revert Errors.ReceiverNotAllowlisted(destChainSelector, receiver);
        }
        s_allowlistedReceivers[destChainSelector].remove(receiver);
        emit ReceiverRemovedFromAllowlist(destChainSelector, receiver);
      }

      if (s_allowlistedReceivers[destChainSelector].length() == 0) {
        s_allowlistedDestinationChains.remove(destChainSelector);
        emit DestinationChainRemovedFromAllowlist(destChainSelector);
      }
    }

    // Process additions next
    for (uint256 i; i < receiversToAdd.length; ++i) {
      uint64 destChainSelector = receiversToAdd[i].destChainSelector;
      bytes[] memory receivers = receiversToAdd[i].receivers;

      for (uint256 j; j < receivers.length; ++j) {
        bytes memory receiver = receivers[j];
        if (!s_allowlistedReceivers[destChainSelector].add(receiver)) {
          revert Errors.ReceiverAlreadyAllowlisted(destChainSelector, receiver);
        }
        emit ReceiverAddedToAllowlist(destChainSelector, receiver);
      }

      if (s_allowlistedDestinationChains.add(destChainSelector)) {
        emit DestinationChainAddedToAllowlist(destChainSelector);
      }
    }
  }

  /// @notice Getter function to retrieve the LINK token used
  /// @return LinkTokenInterface The LINK token
  function getLinkToken() external view returns (LinkTokenInterface) {
    return i_linkToken;
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 interfaceId
  ) public pure override(CCIPReceiver, PausableWithAccessControl) returns (bool) {
    return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IFeeAggregator).interfaceId
      || interfaceId == type(IAccessControlEnumerable).interfaceId
      || interfaceId == type(IAccessControlDefaultAdminRules).interfaceId
      || interfaceId == type(IAccessControl).interfaceId || interfaceId == type(IERC165).interfaceId
      || super.supportsInterface(interfaceId);
  }
}
