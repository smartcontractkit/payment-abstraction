// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract Reserves_SetEarmarksUnitTest is BaseUnitTest {
  Reserves.Earmark[] private s_singleEarmark;
  Reserves.Earmark[] private s_multipleEarmarks;

  modifier whenCallerIsNotEarmarkManager() {
    _changePrank(OWNER);
    _;
  }

  function setUp() public {
    _changePrank(EARMARK_MANAGER);
    s_reserves.addAllowlistedServiceProviders(s_serviceProviders);
    s_singleEarmark.push(Reserves.Earmark(s_serviceProviders[0], 1e18, "earmarkBytes1"));
    s_multipleEarmarks.push(Reserves.Earmark(s_serviceProviders[0], 1e18, "earmarkBytes1"));
    s_multipleEarmarks.push(Reserves.Earmark(s_serviceProviders[1], 2e18, "earmarkBytes2"));
  }

  function test_setEarmarks_SingleEarmarkAmountGtZero() public {
    uint256 earmarkCounter = 1;

    vm.expectEmit(address(s_reserves));
    emit Reserves.EarmarkSet(s_serviceProviders[0], earmarkCounter, 1e18, "earmarkBytes1");

    s_reserves.setEarmarks(s_singleEarmark);

    Reserves.ServiceProvider memory expectedServiceProvider =
      Reserves.ServiceProvider(s_singleEarmark[0].amountLinkOwed, 1);

    _assertServiceProviderEq(s_reserves.getServiceProvider(s_serviceProviders[0]), expectedServiceProvider);
    assertEq(s_reserves.getTotalLinkAmountOwed(), 1e18);
  }

  function test_setEarmarks_MultipleEarmarksAmountGtZero() public {
    // Both service providers are at the same earmarkCounter
    uint256 earmarkCounter = 1;

    vm.expectEmit(address(s_reserves));
    emit Reserves.EarmarkSet(s_serviceProviders[0], earmarkCounter, 1e18, "earmarkBytes1");
    vm.expectEmit(address(s_reserves));
    emit Reserves.EarmarkSet(s_serviceProviders[1], earmarkCounter, 2e18, "earmarkBytes2");

    s_reserves.setEarmarks(s_multipleEarmarks);

    Reserves.ServiceProvider memory expectedServiceProvider1 =
      Reserves.ServiceProvider(s_multipleEarmarks[0].amountLinkOwed, 1);
    Reserves.ServiceProvider memory expectedServiceProvider2 =
      Reserves.ServiceProvider(s_multipleEarmarks[1].amountLinkOwed, 1);

    _assertServiceProviderEq(s_reserves.getServiceProvider(s_serviceProviders[0]), expectedServiceProvider1);
    _assertServiceProviderEq(s_reserves.getServiceProvider(s_serviceProviders[1]), expectedServiceProvider2);
    assertEq(s_reserves.getTotalLinkAmountOwed(), 3e18);
  }

  function test_setEarmarks_MultipleEarmarksAmountLtZero() external {
    s_multipleEarmarks[0].amountLinkOwed = -1e18;
    s_multipleEarmarks[1].amountLinkOwed = -2e18;

    // Both service providers are at the same earmarkCounter
    uint256 earmarkCounter = 1;

    vm.expectEmit(address(s_reserves));
    emit Reserves.EarmarkSet(
      s_serviceProviders[0], earmarkCounter, s_multipleEarmarks[0].amountLinkOwed, "earmarkBytes1"
    );
    vm.expectEmit(address(s_reserves));
    emit Reserves.EarmarkSet(
      s_serviceProviders[1], earmarkCounter, s_multipleEarmarks[1].amountLinkOwed, "earmarkBytes2"
    );

    s_reserves.setEarmarks(s_multipleEarmarks);

    Reserves.ServiceProvider memory expectedServiceProvider1 =
      Reserves.ServiceProvider(s_multipleEarmarks[0].amountLinkOwed, 1);
    Reserves.ServiceProvider memory expectedServiceProvider2 =
      Reserves.ServiceProvider(s_multipleEarmarks[1].amountLinkOwed, 1);

    _assertServiceProviderEq(s_reserves.getServiceProvider(s_serviceProviders[0]), expectedServiceProvider1);
    _assertServiceProviderEq(s_reserves.getServiceProvider(s_serviceProviders[1]), expectedServiceProvider2);
    assertEq(s_reserves.getTotalLinkAmountOwed(), -3e18);
  }

  function test_setEarmarks_RevertWhen_CallerDoesNotHaveTheEARMARK_MANAGER_ROLE() public whenCallerIsNotEarmarkManager {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.EARMARK_MANAGER_ROLE
      )
    );
    s_reserves.setEarmarks(s_multipleEarmarks);
  }

  function test_setEarmarks_RevertWhen_EmptyEarmarkList() public {
    vm.expectRevert(abi.encodeWithSelector(Errors.EmptyList.selector));
    s_reserves.setEarmarks(new Reserves.Earmark[](0));
  }

  function test_setEarmarks_RevertWhen_EarmarkTotalAmountIsGreaterThanReserves() public {
    assertEq(s_mockLINK.balanceOf(address(s_reserves)), FEE_RESERVE_INITIAL_LINK_BALANCE);

    s_multipleEarmarks[0].amountLinkOwed = int96(FEE_RESERVE_INITIAL_LINK_BALANCE);
    s_multipleEarmarks[1].amountLinkOwed = int96(FEE_RESERVE_INITIAL_LINK_BALANCE);

    vm.expectRevert(
      abi.encodeWithSelector(
        Reserves.EarmarksTotalGreaterThanReserves.selector,
        FEE_RESERVE_INITIAL_LINK_BALANCE,
        2 * int96(FEE_RESERVE_INITIAL_LINK_BALANCE)
      )
    );
    s_reserves.setEarmarks(s_multipleEarmarks);
  }

  function _assertEarmarkEq(Reserves.Earmark memory a, Reserves.Earmark memory b) internal {
    assertEq(a.serviceProvider, b.serviceProvider);
    assertEq(a.amountLinkOwed, b.amountLinkOwed);
    assertEq(a.data, b.data);
  }

  function _assertServiceProviderEq(Reserves.ServiceProvider memory a, Reserves.ServiceProvider memory b) internal {
    assertEq(a.linkBalance, b.linkBalance);
    assertEq(a.earmarkCounter, b.earmarkCounter);
  }
}
