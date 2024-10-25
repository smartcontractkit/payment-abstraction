// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {FeeRouter} from "src/FeeRouter.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseTest} from "test/BaseTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract FeeRouter_SetFeeAggregatorUnitTest is BaseTest {
  FeeRouter private s_feeRouter;

  function setUp() public {
    s_feeRouter = new FeeRouter(
      FeeRouter.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: OWNER,
        feeAggregator: makeAddr("FeeAggregator")
      })
    );

    vm.label(address(s_feeRouter), "FeeRouter");
  }

  function test_setFeeAggregator_RevertWhen_CallerDoesNotHaveDEFAULT_ADMIN_ROLE() public whenCallerIsNotAdmin {
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_OWNER, DEFAULT_ADMIN_ROLE)
    );
    s_feeRouter.setFeeAggregator(address(0));
  }

  function test_setFeeAggregator_RevertWhen_FeeAggregatorIsAddressZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    s_feeRouter.setFeeAggregator(address(0));
  }

  function test_setFeeAggregator_RevertWhen_NewFeeAggregatorEqOldFeeAggregator() public {
    vm.mockCall(makeAddr("FeeAggregator"), abi.encodeWithSelector(IERC165.supportsInterface.selector), abi.encode(true));

    vm.expectRevert(Errors.FeeAggregatorNotUpdated.selector);
    s_feeRouter.setFeeAggregator(makeAddr("FeeAggregator"));
  }

  function test_setFeeAggregator_RevertWhen_NewFeeAggregatorDoesNotSupportIFeeAggregatorInterface() public {
    address invalidFeeAggregator = makeAddr("InvalidFeeAggregator");
    vm.mockCall(invalidFeeAggregator, abi.encodeWithSelector(IERC165.supportsInterface.selector), abi.encode(false));

    vm.expectRevert(abi.encodeWithSelector(FeeRouter.InvalidFeeAggregator.selector, invalidFeeAggregator));
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
