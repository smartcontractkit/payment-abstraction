// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract ConstructorUnitTests is BaseUnitTest {
  function test_constructor_RevertWhen_LINKAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: address(0),
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );
  }

  function test_constructor() public {
    vm.expectEmit();
    emit FeeAggregator.LinkTokenSet(MOCK_LINK);
    vm.expectEmit();
    emit FeeAggregator.CCIPRouterClientSet(MOCK_CCIP_ROUTER_CLIENT);
    new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: OWNER,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: MOCK_LINK,
        ccipRouterClient: MOCK_CCIP_ROUTER_CLIENT
      })
    );
    assertEq(address(s_feeAggregatorReceiver.getLinkToken()), MOCK_LINK);
    assertEq(address(s_feeAggregatorReceiver.getRouter()), MOCK_CCIP_ROUTER_CLIENT);
  }

  function test_typeAndVersion() public {
    assertEq(keccak256(bytes(s_feeAggregatorReceiver.typeAndVersion())), keccak256(bytes("Fee Aggregator 1.0.0")));
  }
}
