// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LinkReceiver} from "src/LinkReceiver.sol";
import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Reserves_ConstructorUnitTests is BaseUnitTest {
  function test_constructor() public {
    vm.expectEmit();
    emit LinkReceiver.LinkTokenSet(address(i_mockLink));

    new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(i_mockLink)
      })
    );

    assertEq(s_reserves.typeAndVersion(), "Reserves 1.0.0");
    assertEq(address(s_reserves.getLinkToken()), address(i_mockLink));

    // Verify the contract properly reports its LINK balance
    vm.mockCall(
      address(i_mockLink), abi.encodeWithSelector(IERC20.balanceOf.selector, address(s_reserves)), abi.encode(100)
    );
    assertEq(s_reserves.linkAvailableForPayment(), 100);
  }

  function test_constructor_RevertWhen_LINKAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(0)
      })
    );
  }
}
