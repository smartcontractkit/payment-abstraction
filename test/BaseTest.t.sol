// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FeeAggregator} from "src/FeeAggregator.sol";

import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Constants} from "test/Constants.t.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test} from "forge-std/Test.sol";

contract BaseTest is Constants, Test {
  modifier givenContractIsPaused(
    address contractAddress
  ) {
    (, address msgSender,) = vm.readCallers();
    _changePrank(PAUSER);
    PausableWithAccessControl(contractAddress).emergencyPause();
    _changePrank(msgSender);
    _;
  }

  modifier givenContractIsNotPaused(
    address contractAddress
  ) {
    (, address msgSender,) = vm.readCallers();
    _changePrank(UNPAUSER);
    PausableWithAccessControl(contractAddress).emergencyUnpause();
    _changePrank(msgSender);
    _;
  }

  modifier whenCallerIsNotAdmin() {
    _changePrank(NON_OWNER);
    _;
  }

  modifier whenCallerIsNotAssetManager() {
    _changePrank(OWNER);
    _;
  }

  modifier whenCallerIsNotWithdrawer() {
    _changePrank(OWNER);
    _;
  }

  constructor() {
    vm.startPrank(OWNER);
  }

  function _getAssetPrice(
    AggregatorV3Interface oracle
  ) internal view returns (uint256) {
    (, int256 answer,,,) = oracle.latestRoundData();

    return uint256(answer);
  }

  function _changePrank(
    address newCaller
  ) internal {
    vm.stopPrank();
    vm.startPrank(newCaller);
  }

  function _changePrank(address newCaller, address tx_origin) internal {
    vm.stopPrank();
    vm.startPrank(newCaller, tx_origin);
  }

  /// @notice Empty test function to ignore file in coverage report
  function test_baseTest() public {}
}
