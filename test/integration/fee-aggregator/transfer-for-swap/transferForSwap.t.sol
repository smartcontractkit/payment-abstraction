// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract FeeAggregator_TransferForSwapIntegrationTest is BaseIntegrationTest {
  address[] private s_assets;
  uint256[] private s_amounts;

  modifier whenCallerIsNotSwapAutomator() {
    _changePrank(OWNER);
    _;
  }

  function setUp() public {
    s_assets.push(address(s_mockWETH));
    s_assets.push(address(s_mockUSDC));
    s_amounts.push(10 ether);
    s_amounts.push(10_000e6);

    deal(address(s_mockWETH), address(s_feeAggregatorReceiver), 10 ether);
    deal(address(s_mockUSDC), address(s_feeAggregatorReceiver), 10_000e6);

    _changePrank(ASSET_ADMIN);
    s_feeAggregatorReceiver.applyAllowlistedAssetUpdates(new address[](0), s_assets);

    _changePrank(address(s_swapAutomator));
  }

  function test_transferForSwap_RevertWhen_CallerIsNotSwapAutomator() public whenCallerIsNotSwapAutomator {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.SWAPPER_ROLE)
    );
    s_feeAggregatorReceiver.transferForSwap(OWNER, s_assets, s_amounts);
  }

  function test_transferForSwap_RevertWhen_EmptyAssetList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), new address[](0), new uint256[](0));
  }

  function test_transferForSwap_RevertWhen_AmountZero() public {
    s_amounts[0] = 0;

    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assets, s_amounts);
  }

  function test_transferForSwap_RevertWhen_AssetNotAllowlisted() public {
    MockERC20 asset = new MockERC20();
    asset.initialize("Not Allowlisted Asset", "MOCK", 18);

    s_assets.push(address(asset));
    s_amounts.push(1 ether);

    deal(address(asset), address(s_feeAggregatorReceiver), 1 ether);

    vm.expectRevert(abi.encodeWithSelector(Errors.AssetNotAllowlisted.selector, address(asset)));
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assets, s_amounts);
  }

  function test_transferForSwap_RevertWhen_Paused() public givenContractIsPaused(address(s_feeAggregatorReceiver)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assets, s_amounts);
  }

  function test_transferForSwap() public {
    vm.expectEmit();
    emit FeeAggregator.AssetTransferredForSwap(address(s_swapAutomator), s_assets[0], s_amounts[0]);
    vm.expectEmit();
    emit FeeAggregator.AssetTransferredForSwap(address(s_swapAutomator), s_assets[1], s_amounts[1]);

    s_feeAggregatorReceiver.transferForSwap(address(s_swapAutomator), s_assets, s_amounts);

    assertEq(s_mockWETH.balanceOf(address(s_swapAutomator)), s_amounts[0]);
    assertEq(s_mockUSDC.balanceOf(address(s_swapAutomator)), s_amounts[1]);
    assertEq(s_mockWETH.balanceOf(address(s_feeAggregatorReceiver)), 0);
    assertEq(s_mockUSDC.balanceOf(address(s_feeAggregatorReceiver)), 0);
  }
}
