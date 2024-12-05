// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {Test} from "forge-std/Test.sol";

/// @title This contract is used to mock the Uniswap V3 SwapRouter contract
contract MockUniswapRouter is Test {
  address private immutable i_linkToken;
  address private immutable i_feeAggregatorReceiver;

  /// @notice The mapping of assets to the amount of LINK to receive after swapping the asset
  mapping(address => uint256) private s_amountOut;

  constructor(
    address linkToken
  ) {
    i_linkToken = linkToken;
  }

  /// @notice This function is used to set the amount of LINK to receive after swapping an asset
  /// @param token The address of the asset
  /// @param amountOut The amount of LINK to receive after swapping the asset
  function setAmountOut(address token, uint256 amountOut) external {
    s_amountOut[token] = amountOut;
  }

  /// @notice This function is used to perform a swap
  /// @param params The swap parameters
  function exactInput(
    IV3SwapRouter.ExactInputParams calldata params
  ) external returns (uint256) {
    address asset = address(bytes20(params.path));

    uint256 amountOut = s_amountOut[asset];

    if (amountOut < params.amountOutMinimum) {
      revert("Too little received");
    }

    deal(i_linkToken, params.recipient, IERC20(i_linkToken).balanceOf(params.recipient) + amountOut);

    return amountOut;
  }

  function test_mockUniswapRouterTest() public {}
}
