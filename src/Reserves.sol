// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {EmergencyWithdrawer} from "src/EmergencyWithdrawer.sol";
import {LinkReceiver} from "src/LinkReceiver.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Roles} from "src/libraries/Roles.sol";

import {ILinkAvailable} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/automation/ILinkAvailable.sol";
import {ITypeAndVersion} from "@chainlink/contracts/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice This contract manages the earmarking of funds for service providers
contract Reserves is EmergencyWithdrawer, LinkReceiver, ITypeAndVersion, ILinkAvailable {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;

  /// @notice This error is thrown when the total amount owed to service providers is greater than
  /// the contract's current reserves
  /// @param currentReserves The current reserves of the contract
  /// @param totalAmountOwed The total amount owed to service providers
  error EarmarksTotalGreaterThanReserves(uint256 currentReserves, uint256 totalAmountOwed);
  /// @notice This error is thrown when a service provider has an insufficient earmarked Link balance to withdraw
  /// @param linkBalance The current link balance of the service provider
  error InsufficientEarmarkBalance(int96 linkBalance);
  /// @notice This error is thrown when the service provider is not allowlisted when setting an earmark
  /// @param serviceProvider The address of the service provider
  error ServiceProviderNotAllowlisted(address serviceProvider);

  /// @notice This event is emitted when an earmark is set for a service provider
  /// @param serviceProvider The address of the service provider
  /// @param earmarkCounter The current value of the service provider's earmark counter
  /// @param amountLinkOwed The amount owed to the service provider denominated in juels
  /// @param earmarkData Arbitrary data associated with the earmark
  event EarmarkSet(
    address indexed serviceProvider, uint256 indexed earmarkCounter, int96 amountLinkOwed, bytes earmarkData
  );
  /// @notice This event is emitted when a service provider's balance is withdrawn
  /// @param serviceProvider The address of the service provider
  /// @param amount The amount withdrawn
  event Withdrawn(address indexed serviceProvider, uint256 amount);
  /// @notice This event is emitted when a service provider is removed from the allowlist
  /// @param serviceProvider The address of the service provider
  event ServiceProviderRemovedFromAllowlist(address indexed serviceProvider);
  /// @notice This event is emitted when a service provider is added to the allowlist
  /// @param serviceProvider The address of the service provider
  event ServiceProviderAllowlisted(address indexed serviceProvider);

  /// @notice This struct contains the parameters required to initialize the contract
  struct ConstructorParams {
    uint48 adminRoleTransferDelay; // ─╮ The minimum amount of seconds that must pass before
    //                                 │ the admin address can be transferred
    address admin; // ─────────────────╯ The address of the admin
    address linkToken; //                The address of the LINK token
  }

  /// @notice This struct contains the details for an earmark. An earmark represents one single payout to one service
  /// provider, together with data that determines the details of the earmark. The data can be different between
  /// different earmarks, and should be encoded & decoded off-chain.
  struct Earmark {
    address serviceProvider; // ─╮ The address of the service provider
    int96 amountLinkOwed; // ────╯ The amount of LINK in juels owed to the service provider. This value can be
      //                           negative in the case of a correction.
    bytes data; //                 Arbitrary data associated with the earmark
  }

  /// @notice This struct contains a service provider's earmark counter and balance.
  /// @dev linkBalance There is no risk of balance over/underflow here because type(int96).max >
  /// LINK.totalSupply()
  struct ServiceProvider {
    int96 linkBalance; // ─────╮ LINK balance in juels owed to the service provider. This value
      //                       | can be negative in the case of a correction.
    uint96 earmarkCounter; // ─╯ Running counter used to track unique earmark IDs. The value represents the
      //                         number of earmarks that the service provider currently has.
  }

  /// @inheritdoc ITypeAndVersion
  string public constant override typeAndVersion = "Reserves 1.0.0";

  /// @notice The total amount of LINK the reserves contract owes to service providers
  /// @dev This value is only ever positive even though service providers can have negative balances. If a service
  /// provider has a negative balance, their contribution to this value is 0.
  /// @dev This value is used to ensure that the contract has enough LINK to pay service providers when setting
  /// earmarks.
  uint256 private s_totalLinkAmountOwed;
  /// @notice The set of allowlisted service providers
  EnumerableSet.AddressSet private s_allowlistedServiceProviders;

  /// @notice Mapping of service provider addresses to their respective earmark counter and balance
  mapping(address serviceProvider => ServiceProvider serviceProviderInfo) private s_serviceProviders;

  constructor(
    ConstructorParams memory params
  ) EmergencyWithdrawer(params.adminRoleTransferDelay, params.admin) LinkReceiver(params.linkToken) {}

  // ================================================================
  // │                           Earmarks                           │
  // ================================================================

  /// @notice This function sets earmarks for a set service providers
  /// @dev precondition The caller must have the EARMARK_MANAGER_ROLE
  /// @dev precondition The list of earmarks must not be empty
  /// @dev precondition The service provider must be allowlisted
  /// @param earmarks The list of earmarks to set
  function setEarmarks(
    Earmark[] calldata earmarks
  ) external onlyRole(Roles.EARMARK_MANAGER_ROLE) {
    if (earmarks.length == 0) {
      revert Errors.EmptyList();
    }

    uint256 totalAmountOwed = s_totalLinkAmountOwed;

    for (uint256 i; i < earmarks.length; ++i) {
      if (!s_allowlistedServiceProviders.contains(earmarks[i].serviceProvider)) {
        revert ServiceProviderNotAllowlisted(earmarks[i].serviceProvider);
      }

      address serviceProvider = earmarks[i].serviceProvider;
      ServiceProvider memory serviceProviderInfo = s_serviceProviders[serviceProvider];

      int96 amountLinkOwed = earmarks[i].amountLinkOwed;
      int96 currentBalance = serviceProviderInfo.linkBalance;
      int96 newBalance = currentBalance + amountLinkOwed;
      // A service provider's balance can be negative in the case of a correction, however the total amount owed is
      // equal to the sum of all positive balances.
      // If the current balance is positive, we subtract it from the total amount owed. We add the new balance back to
      // the total if it is positive.
      if (currentBalance > 0) {
        totalAmountOwed -= uint256(int256(currentBalance));
      }
      if (newBalance > 0) {
        // The balance is positive, so we add it to the total amount owed
        totalAmountOwed += uint256(int256(newBalance));
      }

      uint256 earmarkCounter = ++serviceProviderInfo.earmarkCounter;
      serviceProviderInfo.linkBalance = newBalance;

      s_serviceProviders[serviceProvider] = serviceProviderInfo;

      emit EarmarkSet(serviceProvider, earmarkCounter, amountLinkOwed, earmarks[i].data);
    }

    uint256 currentReserves = i_linkToken.balanceOf(address(this));

    if (totalAmountOwed > currentReserves) {
      revert EarmarksTotalGreaterThanReserves(currentReserves, totalAmountOwed);
    }

    s_totalLinkAmountOwed = totalAmountOwed;
  }

  /// @notice Getter function to retrieve the total amount of LINK owed to service providers
  /// @return totalLinkAmountOwed The total amount owed to service providers
  function getTotalLinkAmountOwed() external view returns (uint256 totalLinkAmountOwed) {
    return s_totalLinkAmountOwed;
  }

  // ================================================================
  // │                      Service Providers                       │
  // ================================================================

  /// @notice This function withdraws outstanding balances for a set of service providers
  /// @dev precondition The list of service providers must not be empty
  /// @dev precondition The balance of the service provider must be greater than 0
  /// @dev precondition The contract must not be paused
  /// @param serviceProviders The list of service providers to withdraw the balance for
  function withdraw(
    address[] calldata serviceProviders
  ) external whenNotPaused {
    if (serviceProviders.length == 0) {
      revert Errors.EmptyList();
    }

    uint256 totalAmountOwed = s_totalLinkAmountOwed;

    for (uint256 i; i < serviceProviders.length; ++i) {
      address serviceProvider = serviceProviders[i];

      ServiceProvider storage serviceProviderInfo = s_serviceProviders[serviceProvider];

      int96 linkBalance = serviceProviderInfo.linkBalance;

      if (serviceProviderInfo.linkBalance <= 0) {
        revert InsufficientEarmarkBalance(linkBalance);
      }

      uint256 linkWithdrawn = uint256(int256(linkBalance));

      serviceProviderInfo.linkBalance = 0;
      totalAmountOwed -= linkWithdrawn;

      i_linkToken.safeTransfer(serviceProvider, linkWithdrawn);

      emit Withdrawn(serviceProvider, linkWithdrawn);
    }

    s_totalLinkAmountOwed = totalAmountOwed;
  }

  /// @notice This function adds service providers to the allowlist
  /// @dev precondition The caller must have the EARMARK_MANAGER_ROLE
  /// @dev precondition The service provider list must not be empty
  /// @param serviceProviders The list of service providers to add
  function addAllowlistedServiceProviders(
    address[] calldata serviceProviders
  ) external onlyRole(Roles.EARMARK_MANAGER_ROLE) {
    if (serviceProviders.length == 0) {
      revert Errors.EmptyList();
    }

    for (uint256 i; i < serviceProviders.length; ++i) {
      if (serviceProviders[i] == address(0)) {
        revert Errors.InvalidZeroAddress();
      }

      if (s_allowlistedServiceProviders.add(serviceProviders[i])) {
        emit ServiceProviderAllowlisted(serviceProviders[i]);
      }
    }
  }

  /// @notice This function removes service providers from the allowlist
  /// @dev precondition The caller must have the EARMARK_MANAGER_ROLE
  /// @dev precondition The service provider list must not be empty
  /// @param serviceProviders The list of service providers to remove
  function removeAllowlistedServiceProviders(
    address[] calldata serviceProviders
  ) external onlyRole(Roles.EARMARK_MANAGER_ROLE) {
    if (serviceProviders.length == 0) {
      revert Errors.EmptyList();
    }

    for (uint256 i; i < serviceProviders.length; ++i) {
      if (s_allowlistedServiceProviders.remove(serviceProviders[i])) {
        emit ServiceProviderRemovedFromAllowlist(serviceProviders[i]);
      }
    }
  }

  /// @notice Getter function to check if a service provider is allowlisted
  /// @param serviceProvider The address of the service provider
  /// @return isAllowlisted True if the service provider is allowlisted, false otherwise
  function isServiceProviderAllowlisted(
    address serviceProvider
  ) external view returns (bool isAllowlisted) {
    return s_allowlistedServiceProviders.contains(serviceProvider);
  }

  /// @notice Getter function to retrieve a service provider earmarkCounter and balance
  /// @param serviceProviderAddress The address of the service provider
  /// @return serviceProvider The service provider's earmarkCounter and balance
  function getServiceProvider(
    address serviceProviderAddress
  ) external view returns (ServiceProvider memory serviceProvider) {
    return s_serviceProviders[serviceProviderAddress];
  }

  // ================================================================
  // │                            LINK Token                        │
  // ================================================================

  /// @inheritdoc ILinkAvailable
  function linkAvailableForPayment() external view returns (int256 linkBalance) {
    // LINK balance is returned as an int256 to match the interface
    // It will never be negative and will always fit in an int256 since the max
    // supply of LINK is 1e27
    return int256(i_linkToken.balanceOf(address(this)));
  }
}
