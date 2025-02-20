// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseForkTest} from "test/fork/BaseForkTest.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NativeTokenReceiver_ReceiveForkTest is BaseForkTest {
  function setUp() public {
    deal(i_owner, 10 ether);
  }

  function test_receive_WrappedNativeTokenSetWrapOnReceive() public {
    (bool success,) = address(s_feeAggregatorReceiver).call{value: 1 ether}("");

    assertTrue(success);
    assertEq(i_owner.balance, 9 ether);
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), 1 ether);
  }

  function test_receive_WrappedNativeTokenSetNoWrapOnReceive() public {
    payable(address(s_feeAggregatorReceiver)).transfer(1 ether);

    assertEq(i_owner.balance, 9 ether);
    assertEq(address(s_feeAggregatorReceiver).balance, 1 ether);
  }

  function test_receive_WrappedNativeTokenSetWrapOnReceiveWithoutDepositSupport() public {
    s_feeAggregatorReceiver.setWrappedNativeToken(WBTC);

    payable(address(s_feeAggregatorReceiver)).transfer(1 ether);

    assertEq(i_owner.balance, 9 ether);
    assertEq(address(s_feeAggregatorReceiver).balance, 1 ether);
  }

  function test_receive_WrappedNativeTokenNotSetNoWrapOnReceive() public {
    s_feeAggregatorReceiver.setWrappedNativeToken(address(0));

    payable(address(s_feeAggregatorReceiver)).transfer(1 ether);

    assertEq(i_owner.balance, 9 ether);
    assertEq(address(s_feeAggregatorReceiver).balance, 1 ether);
  }
}
