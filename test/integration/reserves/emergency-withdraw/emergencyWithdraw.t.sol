// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Reserves_EmergencyWithdrawUnitTest is BaseIntegrationTest {
  address[] private s_assets;
  uint256[] private s_amounts;

  modifier giventContractIsNotPaused() {
    _changePrank(UNPAUSER);
    s_reserves.emergencyUnpause();
    _;
  }

  function setUp() public givenContractIsPaused(address(s_reserves)) {
    s_assets.push(address(s_mockLINK));
    s_amounts.push(FEE_RESERVE_INITIAL_LINK_BALANCE);

    deal(address(s_mockLINK), address(s_reserves), FEE_RESERVE_INITIAL_LINK_BALANCE);
  }

  function test_emergencyWithdraw_RevertWhen_TheContractIsNotPaused() external giventContractIsNotPaused {
    vm.expectRevert(Pausable.ExpectedPause.selector);
    _changePrank(PAUSER);
    s_reserves.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_RevertWhen_TheCallerDoesNotHaveTheDEFAULT_ADMIN_ROLE() external whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_reserves.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_RevertWhen_TheAssetListIsEmpty() external {
    vm.expectRevert(Errors.EmptyList.selector);
    s_reserves.emergencyWithdraw(OWNER, new address[](0), new uint256[](0));
  }

  function test_emergencyWithdraw_RevertWhen_AnAssetAddressIsEqualToTheZeroAddress() external {
    s_assets[0] = address(0);
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_reserves.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_RevertWhen_AnAssetAmountIsEqualToZero() external {
    s_amounts[0] = 0;
    vm.expectRevert(Errors.InvalidZeroAmount.selector);
    s_reserves.emergencyWithdraw(OWNER, s_assets, s_amounts);
  }

  function test_emergencyWithdraw_ShouldTransferTheAssetAmountToTheAdminAndEmitEvent() external {
    uint256 balanceBefore = s_mockLINK.balanceOf(OWNER);

    vm.expectEmit(address(s_reserves));
    emit EmergencyWithdrawer.AssetEmergencyWithdrawn(OWNER, address(s_mockLINK), FEE_RESERVE_INITIAL_LINK_BALANCE);
    s_reserves.emergencyWithdraw(OWNER, s_assets, s_amounts);

    assertEq(s_mockLINK.balanceOf(OWNER), balanceBefore + FEE_RESERVE_INITIAL_LINK_BALANCE);
    assertEq(s_mockLINK.balanceOf(address(s_reserves)), 0);
  }
}
