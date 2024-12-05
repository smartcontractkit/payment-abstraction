// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

abstract contract Constants {
  bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
  address internal constant OWNER = address(101); // Not using 1 one since address has dust WETH for
  // fork test
  address internal constant PAUSER = address(2);
  address internal constant UNPAUSER = address(3);
  address internal constant NON_OWNER = address(4);
  address internal constant FORWARDER = address(5);
  uint48 internal constant DEFAULT_ADMIN_TRANSFER_DELAY = 0;

  address internal constant ASSET_1 = address(6);
  address internal constant ASSET_2 = address(7);
  address internal constant INVALID_ASSET = address(123);
  bytes internal constant SENDER_1 = bytes("8");
  bytes internal constant SENDER_2 = bytes("9");
  bytes internal constant RECEIVER_1 = bytes("8");
  bytes internal constant RECEIVER_2 = bytes("9");
  bytes internal constant RECEIVER_3 = bytes("10");
  uint64 internal constant SOURCE_CHAIN_1 = 2;
  uint64 internal constant SOURCE_CHAIN_2 = 3;
  uint64 internal constant DESTINATION_CHAIN_1 = 2;
  uint64 internal constant DESTINATION_CHAIN_2 = 3;
  uint64 internal constant INVALID_SOURCE_CHAIN = 123;
  uint64 internal constant INVALID_DESTINATION_CHAIN = 123;
  address internal constant MOCK_CCIP_ROUTER_CLIENT = address(10);
  address internal constant BRIDGER = address(11);
  address internal constant ASSET_ADMIN = address(12);
  address internal constant MOCK_LINK = address(13);
  address internal constant ASSET_1_ORACLE = address(14);
  address internal constant ASSET_2_ORACLE = address(15);
  address internal constant MOCK_LINK_USD_FEED = address(16);
  address internal constant MOCK_UNISWAP_ROUTER = address(17);
  address internal constant RECEIVER = address(18);
  address internal constant MOCK_UNISWAP_QUOTER_V2 = address(19);
  address internal constant EARMARK_MANAGER = address(20);
  address internal constant SERVICE_PROVIDER_1 = address(21);
  address internal constant SERVICE_PROVIDER_2 = address(22);
  address internal constant SERVICE_PROVIDER_3 = address(23);
  address internal constant WITHDRAWER = address(24);

  bytes internal constant ASSET_1_SWAP_PATH = bytes("123");
  bytes internal constant ASSET_2_SWAP_PATH = bytes("456");
  bytes internal constant EMPTY_SWAP_PATH = bytes("");
  uint64 internal constant SWAP_INTERVAL = 1 hours;
  uint64 internal constant DESTINATION_CHAIN_SELECTOR = 4949039107694359620;
  uint32 internal constant DESTINATION_CHAIN_GAS_LIMIT = 500_000;
  uint16 internal constant MAX_SLIPPAGE = 200;
  uint128 internal constant MIN_SWAP_SIZE = 1_000e8;
  uint128 internal constant MAX_SWAP_SIZE = 100_000e8;
  uint64 internal constant MAX_GAS_PRICE = 100 gwei;
  uint16 internal constant MAX_PRICE_DEVIATION = 200;
  uint16 internal constant MAX_PRICE_DEVIATION_INVARIANTS = 200;
  uint24 internal constant UNI_POOL_FEE = 3000;
  uint96 internal constant DEADLINE_DELAY = 1 minutes;
  uint96 internal constant MIN_DEADLINE_DELAY = 1 minutes;
  uint96 internal constant MAX_DEADLINE_DELAY = 1 hours;
  uint96 internal constant FEE_RESERVE_INITIAL_LINK_BALANCE = 10 ether;

  bytes32 public constant TEST_ROLE = keccak256("TEST_ROLE");
}
