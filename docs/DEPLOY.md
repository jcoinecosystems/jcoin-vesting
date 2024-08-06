# Deployment instructions


## Install dependencies
```bash
yarn install
```


## Compile, test, deploy and verify Smart Contracts
> Compiler options are defined in the file [/truffle-config.js](/truffle-config.js).


### Compile Smart Contracts
> After successful compilation, smart contract appear in [/flatten](/flatten) folder,
which already include all dependencies in one file.
```bash
yarn compile
```


### Test Smart Contracts
In a different terminal:
```bash
yarn ganache
```

#### Test JcoinTokenVesting
```bash
yarn test
```


### Deploy Smart Contracts
Make `/.env` file from `/.env.example`.

Fill in the environment variable data:
  - MNEMONIC - Seed phrase (24 words) for the deployer wallet.
  - ENDPOINT_SEPOLIA - See [infura.io/](https://infura.io/) or [alchemy.com](https://alchemy.com/) or any public endpoin.
  - ENDPOINT_ETHEREUM - See [infura.io/](https://infura.io/) or [alchemy.com](https://alchemy.com/) or any public endpoin.
  - API_ETHERSCAN - [etherscan.io/myapikey](https://etherscan.io/myapikey).

Set the correct settings in the file (
[/configs/development.js](/configs/development.js),
[/configs/sepolia.js](/configs/sepolia.js)
) for the target network.


#### Deploy JcoinTokenVesting
```bash
yarn deploy sepolia --f 1 --to 10
```


### Verify Smart Contracts
For constructor arguments, please use [abi.hashex.org](https://abi.hashex.org/).
```bash
yarn verify sepolia JcoinTokenVesting
```
