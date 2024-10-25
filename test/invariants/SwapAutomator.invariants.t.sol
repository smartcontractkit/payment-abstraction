// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseInvariant} from "test/invariants/BaseInvariant.t.sol";

contract SwapAutomatorInvariants is BaseInvariant {
  function invariant_swapSlippageShouldNotExceedThreshold() public {
    assertGe(
      s_mockLink.balanceOf(RECEIVER),
      s_upkeepHandler.getTotalAmountOutMinimum(),
      "Invariant violated: total amount out from swaps greater then threshold"
    );
  }

  function test_swapAutomatorInvariants() public {}
}
