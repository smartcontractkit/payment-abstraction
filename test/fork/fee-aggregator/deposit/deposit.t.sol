// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {NativeTokenReceiver} from "src/NativeTokenReceiver.sol";
import {BaseForkTest} from "test/fork/BaseForkTest.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NativeTokenReceiver_DepositForkTest is BaseForkTest {
  function setUp() public {
    deal(address(s_feeAggregatorReceiver), 10 ether);
  }

  function test_deposit() public {
    s_feeAggregatorReceiver.deposit();

    assertEq(address(s_feeAggregatorReceiver).balance, 0 ether);
    assertEq(IERC20(WETH).balanceOf(address(s_feeAggregatorReceiver)), 10 ether);
  }

  function test_deposit_RevertWhen_ZeroBalance() public {
    deal(address(s_feeAggregatorReceiver), 0 ether);

    vm.expectRevert(NativeTokenReceiver.ZeroBalance.selector);
    s_feeAggregatorReceiver.deposit();
  }
}
