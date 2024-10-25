// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract Reserves_ConstructorUnitTests is BaseUnitTest {
  function test_constructor() public {
    vm.expectEmit();
    emit Reserves.LINKTokenSet(address(s_mockLINK));

    new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(s_mockLINK)
      })
    );

    assertEq(s_reserves.typeAndVersion(), "Reserves 1.0.0");
    assertEq(address(s_reserves.getLinkToken()), address(s_mockLINK));

    // Verify the contract properly reports its LINK balance
    deal(address(s_mockLINK), address(s_reserves), 100);
    assertEq(s_reserves.linkAvailableForPayment(), 100);
  }

  function test_constructor_RevertWhen_InvalidZeroAddress() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        linkToken: address(0)
      })
    );
  }
}
