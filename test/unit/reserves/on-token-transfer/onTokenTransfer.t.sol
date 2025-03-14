// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LinkReceiver} from "src/LinkReceiver.sol";
import {Reserves} from "src/Reserves.sol";
import {Errors} from "src/libraries/Errors.sol";
import {BaseUnitTest} from "test/unit/BaseUnitTest.t.sol";

import {MockLinkToken} from "test/mocks/MockLinkToken.sol";

contract Reserves_OnTokenTransferUnitTest is BaseUnitTest {
  MockLinkToken private s_mockLINKToken;

  function setUp() public {
    s_mockLINKToken = new MockLinkToken();
    s_reserves = new Reserves(
      Reserves.ConstructorParams({
        adminRoleTransferDelay: DEFAULT_ADMIN_TRANSFER_DELAY,
        admin: i_owner,
        linkToken: address(s_mockLINKToken)
      })
    );
  }

  function test_onTokenTransfer_RevertWhen_TheSenderIsNotTheLINKToken() external {
    vm.expectRevert(abi.encodeWithSelector(LinkReceiver.SenderNotLinkToken.selector, address(i_owner)));
    s_reserves.onTokenTransfer(address(0), 0, "");
  }

  function test_onTokenTransfer_ShouldTransferTheTokensToTheReserves() external {
    uint256 linkAmount = 100;
    uint256 balanceBefore = s_mockLINKToken.balanceOf(address(s_reserves));
    s_mockLINKToken.transferAndCall(address(s_reserves), linkAmount, "");
    uint256 balanceAfter = s_mockLINKToken.balanceOf(address(s_reserves));
    assertEq(balanceAfter, balanceBefore + linkAmount);
  }
}
