// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {IWERC20} from "@chainlink/contracts/src/v0.8/shared/interfaces/IWERC20.sol";

contract MockWrappedNative is IWERC20, MockERC20 {
  function deposit() external payable override {
    _mint(msg.sender, msg.value);
  }

  function withdraw(
    uint256 amount
  ) external override {}
}
