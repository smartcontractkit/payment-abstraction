# Payment Abstraction

Payment Abstraction is a system of onchain smart contracts that aim to reduce payment friction for Chainlink services. The system is designed to (1) accept fees in various tokens across multiple blockchain networks, (2) consolidate fee tokens onto a single blockchain network via Chainlink CCIP, (3) convert fee tokens into LINK via Chainlink Automation, Price Feeds, and existing Automated Market Maker (AMM) Decentralized Exchange (DEX) contracts, and (4) pass converted LINK into a dedicated contract for withdrawal by Chainlink Network service providers.

Please note: This repository is undergoing a code audit and may not include audit remediations or other updates. 

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

- Note: the `tools/coverage.ignore.json` file tracks the ignored branches for coverage checks. When the line changes, the file also has to be updated. To find the branches that are not covered, the script will print lines that look like:

```
{ line: 298, block: 20, branch: 0, taken: 0 }
```

- The line above means that Line 298, Block 20, first branch is not covered - so we can ignore it:

```
  "FeeAggregator": {
    "branches": [
      {
        "line": 298,
        "block": 20,
        "branch": 0
      }
    ]
  },
```

**Run static analysis on all files:**

```shell
$ slither .
```

**Testing PausableWithAccessControl**

This abstract contract is inherited by many of the contracts in this repo. To ensure full test coverage without
duplicating tests, add the new contract in the following list in `test/unit/BaseUnitTest.t.sol`. The `performForAllContractsPausableWithAccessControl` modifier must be added to all the shared tests.

```
// BaseUnitTest.t.sol
// Add contracts to the list of contracts that are PausableWithAccessControl
s_contractsPausableWithAccessControl.push(address(s_feeAggregatorSender));
s_contractsPausableWithAccessControl.push(address(s_feeAggregatorReceiver));
s_contractsPausableWithAccessControl.push(address(s_swapAutomator));
s_contractsPausableWithAccessControl.push(address(s_reserves));
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
