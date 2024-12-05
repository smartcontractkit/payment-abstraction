// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {NativeTokenReceiver} from "src/NativeTokenReceiver.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract FeeAggregator_setWrappedNativeToken_UnitTest is BaseUnitTest {
  address private s_newWrappedNativeToken = makeAddr("newWrappedNativeToken");

  function test_setWrappedNativeToken() public {
    vm.expectEmit(address(s_feeRouter));
    emit NativeTokenReceiver.WrappedNativeTokenSet(s_newWrappedNativeToken);

    s_feeRouter.setWrappedNativeToken(s_newWrappedNativeToken);

    assertEq(address(s_feeRouter.getWrappedNativeToken()), s_newWrappedNativeToken);
  }

  function test_setWrappedNativeToken_RevertWhen_CallerDoesNotHaveADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeRouter.setWrappedNativeToken(s_newWrappedNativeToken);
  }

  function test_setWrappedNativeToken_RevertWhen_NewWrappedNativeTokenEqOldWrappedNativeToken() public {
    vm.expectRevert(Errors.ValueEqOriginalValue.selector);
    s_feeAggregatorReceiver.setWrappedNativeToken(s_mockWrappedNativeToken);
  }
}
