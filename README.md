# This stablecoin made with:

```shell
1. Relative Stability: Pegged or Anchored -> 1.00$
    1. Chainlink Price feed.
    2. Set a function to exchange ETH & BTC -> $$$
2. Stability Method(Minting): Algorithmic(Decentralized)
    1. People can only mint the stablecoin with enough collateral(coded)
3. Collateral: Exogenous(crypto)
    1. wETH
    2. wBTC
```

## Usage

### To create project

```shell
$ forge init
```

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

### Get coverage details

```shell
$ forge coverage --report debug
```

### To get the function signature and selector of contract

```shell
$ forge inspect <Contract-name> methods
```


### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
