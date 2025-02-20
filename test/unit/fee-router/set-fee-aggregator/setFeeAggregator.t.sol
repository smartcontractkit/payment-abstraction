// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FeeRouter} from "src/FeeRouter.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract FeeRouter_SetFeeAggregatorUnitTest is BaseUnitTest {
  function test_setFeeAggregator_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, i_nonOwner, DEFAULT_ADMIN_ROLE)
    );
    s_feeRouter.setFeeAggregator(address(0));
  }

  function test_setFeeAggregator_RevertWhen_FeeAggregatorIsAddressZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeRouter.setFeeAggregator(address(0));
  }

  function test_setFeeAggregator_RevertWhen_NewFeeAggregatorEqOldFeeAggregator() public {
    vm.mockCall(
      address(s_feeAggregatorReceiver), abi.encodeWithSelector(IERC165.supportsInterface.selector), abi.encode(true)
    );
    vm.expectRevert(Errors.ValueNotUpdated.selector);
    s_feeRouter.setFeeAggregator(address(s_feeAggregatorReceiver));
  }

  function test_setFeeAggregator_RevertWhen_NewFeeAggregatorDoesNotSupportIFeeAggregatorInterface() public {
    address invalidFeeAggregator = makeAddr("InvalidFeeAggregator");
    vm.mockCall(invalidFeeAggregator, abi.encodeWithSelector(IERC165.supportsInterface.selector), abi.encode(false));

    vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFeeAggregator.selector, invalidFeeAggregator));
    s_feeRouter.setFeeAggregator(invalidFeeAggregator);
  }

  function test_setFeeAggregator() public {
    address newFeeAggregator = makeAddr("NewFeeAggregator");
    vm.mockCall(newFeeAggregator, abi.encodeWithSelector(IERC165.supportsInterface.selector), abi.encode(true));

    vm.expectEmit(address(s_feeRouter));
    emit FeeRouter.FeeAggregatorSet(newFeeAggregator);

    s_feeRouter.setFeeAggregator(newFeeAggregator);

    assertEq(address(s_feeRouter.getFeeAggregator()), newFeeAggregator);
  }
}
