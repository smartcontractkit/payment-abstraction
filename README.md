# Payment Abstraction

Payment Abstraction is a system of onchain smart contracts that aim to reduce payment friction for Chainlink services. The system is designed to (1) accept fees in various tokens across multiple blockchain networks, (2) consolidate fee tokens onto a single blockchain network via Chainlink CCIP, (3) convert fee tokens into LINK via Chainlink Automation, Price Feeds, and existing Automated Market Maker (AMM) Decentralized Exchange (DEX) contracts, and (4) pass converted LINK into a dedicated contract for withdrawal by Chainlink Network service providers.

## Usage

### Pre-requisites

- [pnpm](https://pnpm.io/installation)
- [foundry](https://book.getfoundry.sh/getting-started/installation)
- [slither](https://github.com/crytic/slither) (for static analysis)
- Create an `.env` file, following the `.env.example` (some tests will fail without a configured mainnet RPC)

### Build

```shell
$ pnpm foundry
$ pnpm install
$ forge build
```

### Test

**Run all tests:**

```shell
$ forge test
```

**Detailed gas report:**

```shell
$ forge test --gas-report --isolate
```

**Coverage report:**

```shell
$ forge coverage --report lcov
```

**Check coverage:**

```shell
node tools/coverage.cjs
```

- Note: the `tools/coverage.ignore.json` file tracks the ignored contracts for coverage checks (the script natively ignore test and script files). Example:

```
["FeeAggregator"]
```

**Run static analysis on all files:**

```shell
$ slither .
```

**Testing common contracts**

Some abstract contracts such as `EmergencyWithdrawer` are inherited by many of the contracts in this repo. To ensure full test coverage without duplicating tests, add the new contract in the following list from `test/BaseTest.t.sol`:

```solidity
// BaseTest.t.sol
  mapping(CommonContracts commonContracts => address[]) internal s_commonContracts;
```

```solidity
// BaseUnitTest.t.sol
// Add contracts to the list of contracts that are PausableWithAccessControl
s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_feeAggregatorSender));
s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_feeAggregatorReceiver));
s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_swapAutomator));
s_commonContracts[CommonContracts.PAUSABLE_WITH_ACCESS_CONTROL].push(address(s_reserves));
```

The `performForAllContracts` modifier must be added to all the shared tests. This modifier takes in a `CommonContracts` enum type as an argument. If a new shared contract is added a new type should also be added to the enum.

```solidity
enum CommonContracts {
  PAUSABLE_WITH_ACCESS_CONTROL,
  EMERGENCY_WITHDRAWER,
  LINK_RECEIVER
}
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

**Generate snapshot:**

```shell
$ pnpm run snapshot
```

**Compare against existing snapshot:**

```shell
$ pnpm run snapshot --diff
```

### Updating Foundry version

Foundry is fixed to a specific nightly version. To update the version:

- Update the `nightly-<FOUNDRY_VERSION>` field in [package.json](package.json) foundry script.

```json
"foundry": "foundryup --version nightly-fdd321bac95f0935529164a88faf99d4d5cfa321"
```

- Update the foundry version in the [action.yml](.github/actions/setup/action.yml) file.

```yaml
version: nightly-fdd321bac95f0935529164a88faf99d4d5cfa321
```

- Run `pnpm foundry`
