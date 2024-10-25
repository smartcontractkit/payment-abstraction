// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseInvariant} from "test/invariants/BaseInvariant.t.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ReservesInvariant is BaseInvariant {
  using SafeCast for uint256;

  function invariant_SumOfEarmarksSubmittedShouldEqualServiceProvidersLINKBalanceAndAmountOwed() public {
    // Total balance of all service providers
    address[] memory serviceProviders = s_reservesHandler.getServiceProviders();
    uint256 serviceProvidersTotalLINKBalance;
    int96 serviceProvidersFinalAmountOwed;
    for (uint256 i; i < serviceProviders.length; ++i) {
      serviceProvidersTotalLINKBalance += s_mockLink.balanceOf(serviceProviders[i]);
      serviceProvidersFinalAmountOwed += s_reserves.getServiceProvider(serviceProviders[i]).linkBalance;
    }

    // Get the running tally values from the handler contract
    int96 totalEarmarked = s_reservesHandler.getTotalEarmarked();
    uint256 totalWithdrawn = s_reservesHandler.getTotalWithdrawn();

    assertEq(s_reserves.getTotalLinkAmountOwed(), totalEarmarked);
    assertEq(
      int256(totalEarmarked) + totalWithdrawn.toInt256(),
      serviceProvidersTotalLINKBalance.toInt256() + serviceProvidersFinalAmountOwed
    );
  }

  // added to be excluded from coverage report
  function test_reservesInvariant() public {}
}