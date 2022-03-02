# NFT-MarketPlace

## Installation

`npm i`

## Compile/build contracts

`npm run build`

## Run unit-test

- Run all: `npm run test`
- Run coverage: `npm run test-coverage`
- Run only DbiliaToken test: `npm run test-token`
- Run only Marketplace test: `npm run test-marketplace`
- Run only WethReceiver test: `npm run test-wethreceiver`
## Matic network

### Faucet

This faucet provides both test `MATIC` tokens on Matic testnet and test `ETH` tokens on Goerli
https://faucet.matic.network/

## Metamask connection to Matic

To connect Metamask to Matic, please set the `Custom RPC` with the following info:

- `Network Name`: `Matic Mumbai Testnet` or `Matic Mainnet`
- `New RPC URL`: `https://rpc-mumbai.maticvigil.com` (testnet) or `https://rpc-mainnet.maticvigil.com` (mainnet)
- `Chain ID`: `80001` (testnet) or `137` (mainnet)
- `Currency symbol`: `MATIC`
- `Block explorer URL`: `https://mumbai.polygonscan.com/` (testnet) or `https://polygonscan.com/` (mainnet)