// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseForkTest} from "test/fork/BaseForkTest.t.sol";

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract BridgeAssetsForkTest is BaseForkTest {
  using SafeERC20 for IERC20;

  uint256 internal constant BRIDGING_FEE = 1 ether;
  uint256 internal constant USDC_BRIDGED_AMOUNT = 10_000e6;
  address[] private s_assetsToAllowlist;
  FeeAggregator.AllowlistedReceivers[] private s_receiversToAllowlist;
  bytes[] private s_receiverAddresses;

  Client.EVMTokenAmount[] private s_bridgeAssetAmounts;

  modifier givenEnoughLinkBalance() {
    _deal(LINK, address(s_feeAggregatorSender), BRIDGING_FEE);
    _;
  }

  function setUp() public {
    s_bridgeAssetAmounts.push(Client.EVMTokenAmount({token: USDC, amount: USDC_BRIDGED_AMOUNT}));

    // Deal USDC to the FeeAggregator contract
    _deal(USDC, address(s_feeAggregatorSender), USDC_BRIDGED_AMOUNT);

    _changePrank(i_owner);

    // Grant ASSET_ADMIN_ROLE to i_owner if not already granted
    bytes32 assetAdminRole = Roles.ASSET_ADMIN_ROLE;
    if (!s_feeAggregatorSender.hasRole(assetAdminRole, i_owner)) {
      s_feeAggregatorSender.grantRole(assetAdminRole, i_owner);
    }

    // Grant DEFAULT_ADMIN_ROLE to i_owner if not already granted
    bytes32 defaultAdminRole = s_feeAggregatorSender.DEFAULT_ADMIN_ROLE();
    if (!s_feeAggregatorSender.hasRole(defaultAdminRole, i_owner)) {
      s_feeAggregatorSender.grantRole(defaultAdminRole, i_owner);
    }

    s_receiverAddresses.push(abi.encodePacked(i_receiver));
    s_receiversToAllowlist.push(
      FeeAggregator.AllowlistedReceivers({
        remoteChainSelector: DESTINATION_CHAIN_SELECTOR,
        receivers: s_receiverAddresses
      })
    );
    FeeAggregator.AllowlistedReceivers[] memory emptyReceivers = new FeeAggregator.AllowlistedReceivers[](0);
    s_feeAggregatorSender.applyAllowlistedReceiverUpdates(emptyReceivers, s_receiversToAllowlist);

    // Grant BRIDGER_ROLE to i_bridger account
    bytes32 bridgerRole = Roles.BRIDGER_ROLE;
    if (!s_feeAggregatorSender.hasRole(bridgerRole, i_bridger)) {
      s_feeAggregatorSender.grantRole(bridgerRole, i_bridger);
    }

    // Switch to i_bridger account for the tests
    _changePrank(i_bridger);
  }

  function test_bridgeAssets_RevertWhen_ContractIsPaused() public givenContractIsPaused(address(s_feeAggregatorSender)) {
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorSender.bridgeAssets(
      s_bridgeAssetAmounts, DESTINATION_CHAIN_SELECTOR, abi.encodePacked(i_receiver), extraArgs
    );
  }

  function test_bridgeAssets_RevertWhen_CallerIsNotABridger() public {
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);
    _changePrank(i_owner);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.BRIDGER_ROLE)
    );
    s_feeAggregatorSender.bridgeAssets(
      s_bridgeAssetAmounts, DESTINATION_CHAIN_SELECTOR, abi.encodePacked(i_receiver), extraArgs
    );
  }

  function test_bridgeAssets_RevertWhen_BridgingAssetNotOnAllowlist() public {
    s_bridgeAssetAmounts[0].token = i_invalidAsset;
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);
    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, i_invalidAsset));
    s_feeAggregatorSender.bridgeAssets(
      s_bridgeAssetAmounts, DESTINATION_CHAIN_SELECTOR, abi.encodePacked(i_receiver), extraArgs
    );
  }

  function test_bridgeAssets_RevertWhen_ContractCannotPayFee() public {
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);
    vm.mockCall(CCIP_ROUTER, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(BRIDGING_FEE));
    vm.expectRevert(
      abi.encodeWithSelector(
        FeeAggregator.InsufficientBalance.selector, IERC20(LINK).balanceOf(address(s_feeAggregatorSender)), BRIDGING_FEE
      )
    );
    s_feeAggregatorSender.bridgeAssets(
      s_bridgeAssetAmounts, DESTINATION_CHAIN_SELECTOR, abi.encodePacked(i_receiver), extraArgs
    );
  }

  function test_bridgeAssets_SendsCorrectDataToCCIPRouter() public givenEnoughLinkBalance {
    // Assert the contract reports the correct LINK balance
    assertEq(uint256(s_feeAggregatorSender.linkAvailableForPayment()), BRIDGING_FEE);

    uint64 destinationChainSelector = DESTINATION_CHAIN_SELECTOR;
    bytes memory bridgeReceiver = abi.encodePacked(address(s_feeAggregatorReceiver));
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);

    Client.EVMTokenAmount[] memory bridgeAssetAmounts = new Client.EVMTokenAmount[](s_bridgeAssetAmounts.length);
    for (uint256 i = 0; i < s_bridgeAssetAmounts.length; i++) {
      bridgeAssetAmounts[i] = s_bridgeAssetAmounts[i];
    }

    vm.mockCall(CCIP_ROUTER, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(bytes32(0x0)));

    vm.expectCall(USDC, abi.encodeWithSelector(IERC20.approve.selector, CCIP_ROUTER, bridgeAssetAmounts[0].amount));

    _changePrank(i_bridger);

    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.BridgeAssetsMessageSent(
      bytes32(0x0),
      Client.EVM2AnyMessage({
        receiver: bridgeReceiver,
        data: "",
        tokenAmounts: bridgeAssetAmounts,
        extraArgs: extraArgs,
        feeToken: LINK
      })
    );

    s_feeAggregatorSender.bridgeAssets(bridgeAssetAmounts, destinationChainSelector, bridgeReceiver, extraArgs);
  }

  function test_bridgeAssets_AllAbts() public {
    address[] memory allowlistedAssets = s_feeAggregatorSender.getAllowlistedAssets();
    _deal(LINK, address(s_feeAggregatorSender), BRIDGING_FEE);

    Client.EVMTokenAmount[] memory bridgeAssetAmounts = new Client.EVMTokenAmount[](allowlistedAssets.length);

    for (uint256 i; i < allowlistedAssets.length; ++i) {
      _dealSwapAmount(allowlistedAssets[i], address(s_feeAggregatorSender), MAX_SWAP_SIZE);
      bridgeAssetAmounts[i] = Client.EVMTokenAmount({
        token: allowlistedAssets[i],
        amount: IERC20(allowlistedAssets[i]).balanceOf(address(s_feeAggregatorSender))
      });
    }

    // Since we are testing all ABTs on a single chain (fork) not mocking CCIP calls will lead to
    // reverts because not all ABTs are supported on the same chain
    vm.mockCall(CCIP_ROUTER, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(BRIDGING_FEE));
    vm.mockCall(CCIP_ROUTER, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(true));

    vm.expectEmit(address(s_feeAggregatorSender));
    emit FeeAggregator.BridgeAssetsMessageSent(
      bytes32(abi.encode(true)),
      Client.EVM2AnyMessage({
        receiver: abi.encodePacked(i_receiver),
        data: "",
        tokenAmounts: bridgeAssetAmounts,
        extraArgs: _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT),
        feeToken: LINK
      })
    );

    s_feeAggregatorSender.bridgeAssets(
      bridgeAssetAmounts,
      DESTINATION_CHAIN_SELECTOR,
      abi.encodePacked(i_receiver),
      _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT)
    );
  }

  function test_bridgeAssets_RevertWhen_BridgingReceiverIsNotOnAllowlist() public {
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);
    vm.expectRevert(
      abi.encodeWithSelector(
        FeeAggregator.ReceiverNotAllowlisted.selector, INVALID_DESTINATION_CHAIN, abi.encodePacked(i_receiver)
      )
    );
    s_feeAggregatorSender.bridgeAssets(
      s_bridgeAssetAmounts, INVALID_DESTINATION_CHAIN, abi.encodePacked(i_receiver), extraArgs
    );

    address invalidReceiver = address(0);
    vm.expectRevert(
      abi.encodeWithSelector(
        FeeAggregator.ReceiverNotAllowlisted.selector, DESTINATION_CHAIN_SELECTOR, abi.encodePacked(invalidReceiver)
      )
    );
    s_feeAggregatorSender.bridgeAssets(
      s_bridgeAssetAmounts, DESTINATION_CHAIN_SELECTOR, abi.encodePacked(invalidReceiver), extraArgs
    );
  }

  function test_bridgeAssets_RevertWhen_BridgedAssetListIsEmpty() public {
    _deal(LINK, address(s_feeAggregatorSender), BRIDGING_FEE);

    Client.EVMTokenAmount[] memory bridgeAssetAmounts = new Client.EVMTokenAmount[](0);

    vm.expectRevert(Errors.EmptyList.selector);
    s_feeAggregatorSender.bridgeAssets(
      bridgeAssetAmounts,
      DESTINATION_CHAIN_SELECTOR,
      abi.encodePacked(i_receiver),
      _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT)
    );
  }

  function test_bridgeAssets_RevertWhen_IncreaseAllowanceCalledOnNonZeroUSDTAllowance() public givenEnoughLinkBalance {
    _deal(LINK, address(s_feeAggregatorSender), BRIDGING_FEE);

    // 1. Give the FeeAggregator some USDT so it can bridge.
    _deal(USDT, address(s_feeAggregatorSender), USDC_BRIDGED_AMOUNT);

    // 2. Switch msg.sender to the FeeAggregator contract (the actual token holder).
    _changePrank(address(s_feeAggregatorSender));

    // 3. Set a non-zero initial approval. This ensures the allowance is NOT zero
    //    at the time of the first `bridgeAssets` call.
    IERC20(USDT).forceApprove(CCIP_ROUTER, 1);

    // 4. Revert control back to the Bridger role which calls `bridgeAssets`.
    _changePrank(i_bridger);

    // 5. Prepare bridging parameters
    Client.EVMTokenAmount[] memory bridgeAssetAmounts = new Client.EVMTokenAmount[](1);
    bridgeAssetAmounts[0] = Client.EVMTokenAmount({token: USDT, amount: USDC_BRIDGED_AMOUNT});

    uint64 destinationChainSelector = DESTINATION_CHAIN_SELECTOR;
    bytes memory bridgeReceiver = abi.encodePacked(address(s_feeAggregatorReceiver));
    bytes memory extraArgs = _encodeExtraArgs(DESTINATION_CHAIN_GAS_LIMIT);

    // 6. Mock out CCIP calls because the forked CCIP does not support bridging USDT
    vm.mockCall(
      CCIP_ROUTER,
      abi.encodeWithSelector(IRouterClient.ccipSend.selector),
      abi.encode(bytes32(uint256(1))) // Return a fake messageId
    );
    vm.mockCall(
      CCIP_ROUTER,
      abi.encodeWithSelector(IRouterClient.getFee.selector),
      abi.encode(uint256(0)) // Return a 0 LINK fee
    );

    // 7. Bridging call: uses `safeIncreaseAllowance` on top of the existing 1 USDT allowance.
    s_feeAggregatorSender.bridgeAssets(bridgeAssetAmounts, destinationChainSelector, bridgeReceiver, extraArgs);
  }

  function _encodeExtraArgs(
    uint256 gasLimit
  ) internal pure returns (bytes memory) {
    return Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: gasLimit}));
  }
}
