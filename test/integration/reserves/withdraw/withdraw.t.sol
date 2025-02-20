// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Reserves_WithdrawUnitTest is BaseIntegrationTest {
  Reserves.Earmark[] private s_earmarks;

  function setUp() public {
    _changePrank(i_earmarkManager);

    deal(address(s_mockLINK), address(s_reserves), 10e18);
    s_earmarks.push(Reserves.Earmark(s_serviceProviders[0], 4e18, "earmarkBytes1"));
    s_earmarks.push(Reserves.Earmark(s_serviceProviders[1], 6e18, "earmarkBytes2"));
    s_reserves.addAllowlistedServiceProviders(s_serviceProviders);

    s_reserves.setEarmarks(s_earmarks);
  }

  function test_withdraw_SingleServiceProvider() public {
    assertEq(s_mockLINK.balanceOf(address(s_serviceProviders[0])), 0);

    s_serviceProviders.pop();
    vm.accesses(address(s_reserves));
    emit Reserves.Withdrawn(s_serviceProviders[0], uint256(int256(s_earmarks[0].amountLinkOwed)));

    s_reserves.withdraw(s_serviceProviders);

    assertEq(s_mockLINK.balanceOf(address(s_reserves)), uint256(uint96(s_earmarks[1].amountLinkOwed)));
    assertEq(s_mockLINK.balanceOf(address(s_serviceProviders[0])), uint256(uint96(s_earmarks[0].amountLinkOwed)));
  }

  function test_withdraw_MultipleServiceProviders() public {
    assertEq(s_mockLINK.balanceOf(address(s_serviceProviders[0])), 0);
    assertEq(s_mockLINK.balanceOf(address(s_serviceProviders[1])), 0);

    vm.accesses(address(s_reserves));
    emit Reserves.Withdrawn(s_serviceProviders[0], uint256(int256(s_earmarks[0].amountLinkOwed)));
    vm.accesses(address(s_reserves));
    emit Reserves.Withdrawn(s_serviceProviders[1], uint256(int256(s_earmarks[1].amountLinkOwed)));

    s_reserves.withdraw(s_serviceProviders);

    assertEq(s_mockLINK.balanceOf(address(s_serviceProviders[0])), uint256(uint96(s_earmarks[0].amountLinkOwed)));
    assertEq(s_mockLINK.balanceOf(address(s_serviceProviders[1])), uint256(uint96(s_earmarks[1].amountLinkOwed)));
    assertEq(s_mockLINK.balanceOf(address(s_reserves)), 0);
  }

  function test_withdraw_AfterNegativeEarmarkCorrection() public {
    address[] memory serviceProviders = new address[](1);
    serviceProviders[0] = s_serviceProviders[0];
    // Bring the balance of the first service provider to 0
    s_reserves.withdraw(serviceProviders);

    // Check the balance of the service providers
    assertEq(s_reserves.getServiceProvider(s_serviceProviders[0]).linkBalance, 0);
    assertEq(s_reserves.getServiceProvider(s_serviceProviders[1]).linkBalance, s_earmarks[1].amountLinkOwed);

    // Add a negative earmark to the first service provider
    Reserves.Earmark[] memory negativeEarmarks = new Reserves.Earmark[](1);
    negativeEarmarks[0] = Reserves.Earmark(s_serviceProviders[0], -4e18, "earmarkBytes1");
    s_reserves.setEarmarks(negativeEarmarks);

    // Check the balance of the service providers
    assertEq(s_reserves.getServiceProvider(s_serviceProviders[0]).linkBalance, -4e18);
    assertEq(s_reserves.getServiceProvider(s_serviceProviders[1]).linkBalance, s_earmarks[1].amountLinkOwed);

    // Withdraw should be successful for second provider
    serviceProviders[0] = s_serviceProviders[1];
    s_reserves.withdraw(serviceProviders);

    // Check the balance of the service providers
    assertEq(s_reserves.getServiceProvider(s_serviceProviders[0]).linkBalance, -4e18);
    assertEq(s_reserves.getServiceProvider(s_serviceProviders[1]).linkBalance, 0);
  }

  function test_withdraw_RevertWhen_EmptyServiceProviderList() public {
    vm.expectRevert(Errors.EmptyList.selector);
    s_reserves.withdraw(new address[](0));
  }

  function test_withdraw_RevertWhen_InsufficientBalance() public {
    vm.expectRevert(abi.encodeWithSelector(Reserves.InsufficientEarmarkBalance.selector, 0));
    s_serviceProviders.push(address(this));
    s_reserves.withdraw(s_serviceProviders);
  }

  function test_withdraw_RevertWhen_ContractIsPaused() public givenContractIsPaused(address(s_reserves)) {
    vm.expectRevert(Pausable.EnforcedPause.selector);
    s_reserves.withdraw(s_serviceProviders);
  }
}
