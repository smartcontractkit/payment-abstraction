// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract Reserves_RemoveAllowlistedServiceProvidersUnitTest is BaseUnitTest {
  function test_removeAllowlistedServiceProviders_RevertWhen_TheCallerDoesNotHaveTheEARMARK_MANAGER_ROLE() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, Roles.EARMARK_MANAGER_ROLE
      )
    );
    s_reserves.removeAllowlistedServiceProviders(s_serviceProviders);
  }

  function test_removeAllowlistedServiceProviders_RevertWhen_TheServiceProvidersListIsEmpty() public {
    vm.expectRevert(Errors.EmptyList.selector);
    _changePrank(EARMARK_MANAGER);
    s_reserves.removeAllowlistedServiceProviders(new address[](0));
  }

  function test_removeAllowlistedServiceProviders_ShouldEmitsServiceProvidersRemovedEvent() public {
    _changePrank(EARMARK_MANAGER);

    // Add the service providers
    s_reserves.addAllowlistedServiceProviders(s_serviceProviders);

    address[] memory serviceProviders = new address[](1);
    serviceProviders[0] = s_serviceProviders[0];

    vm.expectEmit(address(s_reserves));
    emit Reserves.ServiceProviderRemovedFromAllowlist(s_serviceProviders[0]);

    s_reserves.removeAllowlistedServiceProviders(serviceProviders);
  }

  function test_removeAllowlistedServiceProviders_SkipAlreadyRemovedServiceProvider() public {
    _changePrank(EARMARK_MANAGER);

    // Add the service providers
    s_reserves.addAllowlistedServiceProviders(s_serviceProviders);

    assertTrue(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[0]));
    assertTrue(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[1]));

    // Remove the first service provider
    address[] memory serviceProviders = new address[](1);
    serviceProviders[0] = s_serviceProviders[0];
    s_reserves.removeAllowlistedServiceProviders(serviceProviders);
    assertFalse(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[0]));
    assertTrue(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[1]));

    // Remove the same service provider again with an additional service provider
    s_reserves.removeAllowlistedServiceProviders(s_serviceProviders);
    assertFalse(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[0]));
    assertFalse(s_reserves.isServiceProviderAllowlisted(s_serviceProviders[1]));
  }
}
