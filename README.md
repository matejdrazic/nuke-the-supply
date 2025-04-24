## Nuke The Supply

-> To run tests, please add an .env file and fill out necessary variables as seen in .env.example

If you run into this error while building or testing:
```shell
Error (9640): Explicit type conversion not allowed from "int24" to "uint256".
  --> lib/v3-core/contracts/libraries/TickMath.sol:25:28:
   |
25 |         require(absTick <= uint256(MAX_TICK), 'T');
   |                            ^^^^^^^^^^^^^^^^^
```

Change the line in `TickMath.sol` to following:

`require(absTick <= uint256(uint24(MAX_TICK)), 'T');`


## Written in Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
