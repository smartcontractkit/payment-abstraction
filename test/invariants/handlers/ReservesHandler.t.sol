// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Reserves} from "src/Reserves.sol";
import {Constants} from "test/Constants.t.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract ReservesHandler is Test, Constants {
  using SafeCast for int256;

  int96 private constant LINK_MAX_SUPPLY = 1_000_000_000 ether; // 1 billion LINK
  Reserves private s_reserves;
  MockERC20 private s_mockLink;

  address[] private s_serviceProviders;

  int96 private s_totalEarmarked;
  uint256 private s_totalWithdrawn;

  constructor(Reserves reserves, MockERC20 mockLink, address[] memory serviceProviders) {
    s_reserves = reserves;
    s_mockLink = mockLink;
    s_serviceProviders = serviceProviders;
  }

  function setEarmarks(uint256 serviceProviderIndex, int96 amount) public {
    address serviceProvider = _getServiceProvider(serviceProviderIndex);
    // This bound is to make sure s_totalEarmarked is within the range of the total LINK supply
    int96 earmarkAmount =
      int96(bound(amount, (-1 * LINK_MAX_SUPPLY) - s_totalEarmarked, LINK_MAX_SUPPLY - s_totalEarmarked));
    // make sure the contract has enough link for the earmark in order to avoid reverts
    if (earmarkAmount > 0) {
      deal(
        address(s_mockLink),
        address(s_reserves),
        s_mockLink.balanceOf(address(s_reserves)) + int256(earmarkAmount).toUint256()
      );
    }

    Reserves.Earmark[] memory earmarks = new Reserves.Earmark[](1);
    earmarks[0] = (Reserves.Earmark(serviceProvider, earmarkAmount, ""));
    vm.stopPrank();
    vm.startPrank(EARMARK_MANAGER);
    s_totalEarmarked += earmarkAmount;
    s_reserves.setEarmarks(earmarks);
  }

  function withdraw(
    uint256 serviceProviderIndex
  ) public {
    address serviceProvider = _getServiceProvider(serviceProviderIndex);
    int96 serviceProviderBalance = s_reserves.getServiceProvider(serviceProvider).linkBalance;

    // Withdrawing when the balance is 0 or less will revert
    if (serviceProviderBalance > 0) {
      uint256 toWithdraw = int256(serviceProviderBalance).toUint256();
      address[] memory serviceProviders = new address[](1);
      serviceProviders[0] = serviceProvider;
      s_totalWithdrawn += toWithdraw;
      s_totalEarmarked -= serviceProviderBalance;
      s_reserves.withdraw(serviceProviders);
    }
  }

  function getTotalEarmarked() public view returns (int96) {
    return s_totalEarmarked;
  }

  function getTotalWithdrawn() public view returns (uint256) {
    return s_totalWithdrawn;
  }

  function getServiceProviders() public view returns (address[] memory) {
    return s_serviceProviders;
  }

  function _getServiceProvider(
    uint256 index
  ) private view returns (address) {
    index = bound(index, 0, s_serviceProviders.length - 1);
    return s_serviceProviders[index];
  }

  function test_reservesHandlerTest() public {}
}
