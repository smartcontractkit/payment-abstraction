// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeeAggregator} from "src/FeeAggregator.sol";

import {PausableWithAccessControl} from "src/PausableWithAccessControl.sol";
import {Constants} from "test/Constants.t.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test} from "forge-std/Test.sol";

contract BaseTest is Constants, Test {
  enum CommonContracts {
    PAUSABLE_WITH_ACCESS_CONTROL,
    EMERGENCY_WITHDRAWER,
    LINK_RECEIVER
  }

  address internal immutable i_owner = makeAddr("owner");
  address internal immutable i_pauser = makeAddr("pauser");
  address internal immutable i_unpauser = makeAddr("unpauser");
  address internal immutable i_nonOwner = makeAddr("nonOwner");
  address internal immutable i_bridger = makeAddr("bridger");
  address internal immutable i_assetAdmin = makeAddr("assetAdmin");
  address internal immutable i_tokenManager = makeAddr("tokenManager");
  address internal immutable i_earmarkManager = makeAddr("earmarkManager");
  address internal immutable i_withdrawer = makeAddr("withdrawer");
  address internal immutable i_forwarder = makeAddr("forwarder");
  address internal immutable i_invalidAsset = makeAddr("invalidAsset");
  address internal immutable i_invalidToken = makeAddr("invalidToken");
  address internal immutable i_receiver = makeAddr("receiver");
  address internal immutable i_serviceProvider1 = makeAddr("serviceProvider1");
  address internal immutable i_serviceProvider2 = makeAddr("serviceProvider2");
  address internal immutable i_serviceProvider3 = makeAddr("serviceProvider3");
  address internal immutable i_mockCCIPRouterClient = makeAddr("mockCCIPRouterClient");

  address internal s_contractUnderTest;

  mapping(CommonContracts commonContracts => address[]) internal s_commonContracts;

  modifier givenContractIsPaused(
    address contractAddress
  ) {
    (, address msgSender,) = vm.readCallers();
    _changePrank(i_pauser);
    PausableWithAccessControl(contractAddress).emergencyPause();
    _changePrank(msgSender);
    _;
  }

  modifier givenContractIsNotPaused(
    address contractAddress
  ) {
    (, address msgSender,) = vm.readCallers();
    _changePrank(i_unpauser);
    PausableWithAccessControl(contractAddress).emergencyUnpause();
    _changePrank(msgSender);
    _;
  }

  modifier whenCallerIsNotAdmin() {
    _changePrank(i_nonOwner);
    _;
  }

  modifier whenCallerIsNotAssetManager() {
    _changePrank(i_owner);
    _;
  }

  modifier whenCallerIsNotWithdrawer() {
    _changePrank(i_owner);
    _;
  }

  modifier whenCallerIsNotTokenManager() {
    _changePrank(i_owner);
    _;
  }

  /// @notice This modifier is used to test all contracts that are assigned a CommonContract
  /// Assignation is performed under each base test type's setup / constructor function (e.g. BaseUnitTest)
  /// This avoid code duplication while still making sure contracts are implementing the expected common
  /// functionnalities
  modifier performForAllContracts(
    CommonContracts commonContract
  ) {
    for (uint256 i; i < s_commonContracts[commonContract].length; ++i) {
      s_contractUnderTest = s_commonContracts[commonContract][i];
      _;
    }
  }

  constructor() {
    vm.startPrank(i_owner);
  }

  function _getAssetPrice(
    AggregatorV3Interface usdFeed
  ) internal view returns (uint256) {
    (, int256 answer,,,) = usdFeed.latestRoundData();

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
