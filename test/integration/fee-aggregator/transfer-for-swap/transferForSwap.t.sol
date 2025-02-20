// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {FeeAggregator} from "src/FeeAggregator.sol";
import {Common} from "src/libraries/Common.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract FeeAggregator_TransferForSwapIntegrationTest is BaseIntegrationTest {
  Common.AssetAmount[] private s_assetAmounts;

  modifier whenCallerIsNotSwapAutomator() {
    _changePrank(i_owner);
    _;
  }

  function setUp() public {
    address[] memory allowlistedAssets = new address[](2);
    allowlistedAssets[0] = address(s_mockWETH);
    allowlistedAssets[1] = address(s_mockUSDC);
    s_assetAmounts.push(Common.AssetAmount({asset: address(s_mockWETH), amount: 10 ether}));
    s_assetAmounts.push(Common.AssetAmount({asset: address(s_mockUSDC), amount: 10_000e6}));

    deal(address(s_mockWETH), address(s_feeAggregatorReceiver), 10 ether);
    deal(address(s_mockUSDC), address(s_feeAggregatorReceiver), 10_000e6);

    _changePrank(i_assetAdmin);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), allowlistedAssets);

    _changePrank(address(s_swapAutomator));
  }

  function test_transferForSwap_RevertWhen_CallerIsNotSwapAutomator() public whenCallerIsNotSwapAutomator {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.SWAPPER_ROLE)
    );
    s_feeAggregatorReceiver.transferForSwap(i_owner, s_assetAmounts);
  }

  function test_transferForSwap_RevertWhen_EmptyAssetList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), new Common.AssetAmount[](0));
  }

  function test_transferForSwap_RevertWhen_AmountZero() public {
    s_assetAmounts[0].amount = 0;

    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assetAmounts);
  }

  function test_transferForSwap_RevertWhen_AssetNotAllowlisted() public {
    MockERC20 asset = new MockERC20();
    asset.initialize("Not Allowlisted Asset", "MOCK", 18);

    s_assetAmounts.push(Common.AssetAmount({asset: address(asset), amount: 1 ether}));

    deal(address(asset), address(s_feeAggregatorReceiver), 1 ether);

    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, address(asset)));
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assetAmounts);
  }

  function test_transferForSwap_RevertWhen_Paused() public givenContractIsPaused(address(s_feeAggregatorReceiver)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assetAmounts);
  }

  function test_transferForSwap() public {
    vm.expectEmit();
    emit FeeAggregator.AssetTransferredForSwap(
      address(s_swapAutomator), s_assetAmounts[0].asset, s_assetAmounts[0].amount
    );
    vm.expectEmit();
    emit FeeAggregator.AssetTransferredForSwap(
      address(s_swapAutomator), s_assetAmounts[1].asset, s_assetAmounts[1].amount
    );

    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assetAmounts);

    assertEq(s_mockWETH.balanceOf(address(s_swapAutomator)), s_assetAmounts[0].amount);
    assertEq(s_mockUSDC.balanceOf(address(s_swapAutomator)), s_assetAmounts[1].amount);
    assertEq(s_mockWETH.balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_mockUSDC.balanceOf(address(s_feeAggregatorReceiver)), 0);
  }
}
