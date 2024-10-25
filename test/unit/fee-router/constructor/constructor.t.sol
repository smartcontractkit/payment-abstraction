// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {FeeRouter} from "src/FeeRouter.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract HomeFeeAggregatorSender_ConstructorUnitTest is BaseUnitTest {
  function test_constructor() public {
    FeeRouter.ConstructorParams memory params = FeeRouter.ConstructorParams({
      adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
      admin: OWNER,
      feeAggregator: address(s_feeAggregatorReceiver)
    });

    vm.expectEmit();
    emit FeeRouter.FeeAggregatorSet(address(s_feeAggregatorReceiver));
    FeeRouter feeRouter = new FeeRouter(params);

    assertEq(address(feeRouter.getFeeAggregator()), address(s_feeAggregatorReceiver));
    assertEq(feeRouter.typeAndVersion(), "FeeRouter v1.0.0");
  }

  function test_constructor_RevertWhen_SetFeeAggregatorReceiverToAddressZero() public {
    FeeRouter.ConstructorParams memory params = FeeRouter.ConstructorParams({
      adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
      admin: OWNER,
      feeAggregator: address(0)
    });

    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new FeeRouter(params);
  }
}
