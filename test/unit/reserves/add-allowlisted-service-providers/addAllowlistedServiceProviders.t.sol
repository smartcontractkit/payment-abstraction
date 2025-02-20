// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract Reserves_AddAllowlistedServiceProvidersUnitTest is BaseUnitTest {
  function test_addAllowlistedServiceProviders_RevertWhen_TheCallerDoesNotHaveTheEARMARK_MANAGER_ROLE() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, i_owner, Roles.EARMARK_MANAGER_ROLE
      )
    );
    s_reserves.addAllowlistedServiceProviders(s_serviceProviders);
  }

  function test_addAllowlistedServiceProviders_RevertWhen_TheServiceProvidersListIsEmpty() public {
    vm.expectRevert(Errors.EmptyList.selector);
    _changePrank(i_earmarkManager);
    s_reserves.addAllowlistedServiceProviders(new address[](0));
  }

  function test_addAllowlistedServiceProviders_RevertWhen_ServiceProviderAddressIsZero() public {
    _changePrank(i_earmarkManager);

    address[] memory serviceProviders = new address[](2);
    serviceProviders[0] = s_serviceProviders[0];
    serviceProviders[1] = address(0);

    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_reserves.addAllowlistedServiceProviders(serviceProviders);
  }

  function test_addAllowlistedServiceProviders_ShouldEmitsServiceProvidersAddedEvent() public {
    _changePrank(i_earmarkManager);

    address[] memory serviceProviders = new address[](1);
    serviceProviders[0] = s_serviceProviders[0];

    vm.expectEmit(address(s_reserves));
    emit Reserves.ServiceProviderAllowlisted(s_serviceProviders[0]);

    s_reserves.addAllowlistedServiceProviders(serviceProviders);
  }

  function test_addAllowlistedServiceProviders_SkipAlreadyAllowlistedServiceProvider() public {
    _changePrank(i_earmarkManager);

    // Add the first service provider
    address[] memory serviceProviders = new address[](1);
    serviceProviders[0] = s_serviceProviders[0];
    s_reserves.addAllowlistedServiceProviders(serviceProviders);

    assertTrue(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[0]));
    assertFalse(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[1]));

    // Add the same service provider again with an additional service provider
    s_reserves.addAllowlistedServiceProviders(s_serviceProviders);
    assertTrue(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[0]));
    assertTrue(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[1]));
  }
}
