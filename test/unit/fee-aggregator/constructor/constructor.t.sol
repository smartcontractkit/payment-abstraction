// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {LinkReceiver} from "src/LinkReceiver.sol";
import {NativeTokenReceiver} from "src/NativeTokenReceiver.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

contract ConstructorUnitTests is BaseUnitTest {
  function test_constructor_RevertWhen_LINKAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: address(0),
        ccipRouterClient: i_mockCCIPRouterClient,
        wrappedNativeToken: s_mockWrappedNativeToken
      })
    );
  }

  function test_constructor_RevertWhen_CCIPRouterAddressIsZero() public {
    vm.expectRevert(Errors.InvalidZeroAddress.selector);
    new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: i_mockLink,
        ccipRouterClient: address(0),
        wrappedNativeToken: s_mockWrappedNativeToken
      })
    );
  }

  function test_constructor() public {
    vm.expectEmit();
    emit LinkReceiver.LinkTokenSet(i_mockLink);
    vm.expectEmit();
    emit NativeTokenReceiver.WrappedNativeTokenSet(s_mockWrappedNativeToken);
    vm.expectEmit();
    emit FeeAggregator.CCIPRouterClientSet(i_mockCCIPRouterClient);

    new FeeAggregator(
      FeeAggregator.ConstructorParams({
        admin: i_owner,
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        linkToken: i_mockLink,
        ccipRouterClient: i_mockCCIPRouterClient,
        wrappedNativeToken: s_mockWrappedNativeToken
      })
    );

    assertEq(address(s_feeAggregatorReceiver.getWrappedNativeToken()), s_mockWrappedNativeToken);
    assertEq(address(s_feeAggregatorReceiver.getLinkToken()), i_mockLink);
    assertEq(address(s_feeAggregatorReceiver.getRouter()), i_mockCCIPRouterClient);
  }

  function test_typeAndVersion() public {
    assertEq(keccak256(bytes(s_feeAggregatorReceiver.typeAndVersion())), keccak256(bytes("Fee Aggregator 1.0.0")));
  }
}
