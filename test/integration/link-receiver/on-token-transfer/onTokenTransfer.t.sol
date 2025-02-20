// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";
import {LinkReceiver} from "src/LinkReceiver.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.t.sol";

contract LinkReceiver_OnTokenTransferUnitTest is BaseIntegrationTest {
  function test_onTokenTransfer_RevertWhen_TheSenderIsNotTheLINKToken()
    external
    performForAllContracts(CommonContracts.LINK_RECEIVER)
  {
    vm.expectRevert(abi.encodeWithSelector(LinkReceiver.SenderNotLinkToken.selector, address(i_owner)));
    LinkReceiver(s_contractUnderTest).onTokenTransfer(address(0), 0, "");
  }

  function test_onTokenTransfer_ShouldTransferTheTokens()
    external
    performForAllContracts(CommonContracts.LINK_RECEIVER)
  {
    deal(address(s_mockLINK), s_contractUnderTest, 0);
    uint256 linkAmount = 100;
    uint256 balanceBefore = s_mockLINK.balanceOf(s_contractUnderTest);
    s_mockLINK.transferAndCall(s_contractUnderTest, linkAmount, "");
    uint256 balanceAfter = s_mockLINK.balanceOf(s_contractUnderTest);
    assertEq(balanceAfter, balanceBefore + linkAmount);
  }
}
