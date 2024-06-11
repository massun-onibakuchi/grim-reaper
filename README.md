<img align="right" width="150" height="150" top="100" src="./assets/blueprint.png">

# Reaper • [![ci](https://github.com/massun-onibakuchi/grim-reaper/actions/workflows/ci.yaml/badge.svg)](https://github.com/massun-onibakuchi/grim-reaper/actions/workflows/ci.yaml) ![license](https://img.shields.io/badge/License-MIT-green.svg?label=license) ![solidity](https://img.shields.io/badge/solidity-^0.8.15-lightgrey)

## Getting Started

This is [grim-reaper](https://github.com/massun-onibakuchi/grim-reaper): EVM-based on-chain liquidation bot for Aave V3 built with Huff language. Optimized for gas efficiency.
This repo doesn't include any off-chain architecture.

### Requirements

The following will need to be installed. Please follow the links and instructions.

- [Foundry](https://github.com/gakonst/foundry)
- [Huff Compiler](https://docs.huff.sh/get-started/installing/)

### Quickstart

1. Install dependencies

Once you've cloned and entered into your repository, you need to install the necessary dependencies. In order to do so, simply run:

```shell
pnpm install
forge install
```

2. Build & Test

To build and test your contracts, you can run:

```shell
forge build
forge test
```

For more information on how to use Foundry, check out the [Foundry Github Repository](https://github.com/foundry-rs/foundry/tree/master/forge) and the [foundry-huff library repository](https://github.com/huff-language/foundry-huff).

| Single Liquidation (Optimizer runs: 200) | Gas Used | Bytecode Size (kB) |
| ---------------------------------------- | -------- | ------------------ |
| Solidity Contract                        | 94877    | 1.039              |
| Assembly                                 | 94024    | 0.336              |
| Assembly (GrimReaper L2)                 | 94060    | 0.350 + table      |
| Huff Contract                            | 93942    | 0.248              |
| Huff Contract (GrimReaper L2)            | 93976    | 0.260 + table      |

| Single Liquidation (Optimizer runs: 10_000_000) | Gas Used | Bytecode Size (kB) |
| ----------------------------------------------- | -------- | ------------------ |
| Solidity Contract                               | 94301    | 1.342              |
| Assembly                                        | 93508    | 0.363              |
| Assembly (GrimReaper L2)                        | 93544    | 0.377 + table      |
| Huff Contract                                   | 93438    | 0.248              |
| Huff Contract (GrimReaper L2)                   | 93472    | 0.260 + table      |

> `66270` gas is used for the liquidation logic itself on mock Aave v3 pool.

> Note: Optimizer runs affects how well the compiler optimizes tests contract as well. So, it affects measurements.

- solc version: 0.8.24, evm version: cancun with `bytecode_hash = "none"` and `cbor_metadata = false`.
- `forge test -vv --mt=testGas_Liquidate`

## Further Optimization Ideas

- Support limited kinds of collateral tokens and remove `collateral` parameter from main entrypoint
  - [x] O(1) selector table for token addresses to remove calldata size. (`GrimReaper L2`)
  - [ ] Approve once on contract deployment instead of every liquidation
- Replace `jumpi` with other operations
  - [x] Use `mload(type(uint256).max)` for `jumpi` if-else-revert pattern (`GrimReaperHuff`)
- [x] Abuse `returndatasize`, `calldatasize`, `chainid` and `msize` for `push` operations (`GrimReaperHuff`)

## Acknowledgements

- [subway](https://github.com/libevm/subway#subway)
- [subway-rs](https://github.com/abigger87/subway-rs)
- [huff-examples](https://github.com/huff-language/huff-examples)

## Disclaimer

_These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the user interface or the smart contracts. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk._
