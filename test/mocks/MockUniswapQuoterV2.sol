// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title This contract is used to mock the Uniswap V3 SwapRouter contract
contract MockUniswapQuoterV2 {
  uint160[] private s_sqrtPriceX96AfterList;
  uint32[] private s_initializedTicksCrossedList;
  uint256 private s_gasEstimate;

  /// @notice The mapping of assets to the quoted amount of LINK to receive
  mapping(address => uint256) private s_amountOut;

  function setAssetQuoterAmountOut(address asset, uint256 amoutOut) external {
    s_amountOut[asset] = amoutOut;
  }

  function quoteExactInput(
    bytes calldata path,
    uint256
  )
    external
    view
    returns (
      uint256 amountOut,
      uint160[] memory sqrtPriceX96AfterList,
      uint32[] memory initializedTicksCrossedList,
      uint256 gasEstimate
    )
  {
    address asset = address(bytes20(path));

    return (s_amountOut[asset], sqrtPriceX96AfterList, initializedTicksCrossedList, s_gasEstimate);
  }

  // For skipping this file to be ran in the test.
  function test_mockUniswapQuoterV2Test() public {}
}
