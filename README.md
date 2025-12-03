## About
This repo helps setting up local testnet for go-zond and qrysm.

## Prerequisites
You need to have these installed first before continue
1. jq
2. gobrew
3. hexseed-from-address

To install `hexseed-from-address`, run this

```bash
npm i -g @theqrl/hexseed-from-address
```

Then, clone go-zond and qrysm repo

```bash
$ git clone https://github.com/theQRL/qrysm.git
$ git clone https://github.com/theQRL/go-zond.git
``` 

## Setup

Make and move into directory where you want to run local testnet.

```bash
$ mkdir local-testnet
$ cd local-testnet
$ mkdir bin
```

Then, build required binary to run local-testnet, you just need to run this once at the start (note directories where you clone go-zond and qrysm).

```bash
$ gobrew use 1.21.5
$ cd go-zond/
$ make all
$ cp build/bin/gzond local-testnet/bin/
$ cp build/bin/bootnode local-testnet/bin/

$ cd qrysm/
$ go build -o=local-testnet/bin/beacon-chain ./cmd/beacon-chain
$ go build -o=local-testnet/bin/validator ./cmd/validator
$ go build -o=local-testnet/bin/qrysmctl ./cmd/qrysmctl
$ go build -o=local-testnet/bin/deposit ./cmd/staking-deposit-cli/deposit
```

## Run

To run local-testnet, you can simply run `start-testnet.sh` script in root directory. You can change `NUM_NODES` value to the number of nodes you want in the local testnet.

```bash
bash ./start-testnet.sh
```

To stop local testnet, run `stop-testnet.sh` script.

```bash
bash ./stop-testnet.sh
```

## Send transaction

While local testnet is running, you can simulate sending transaction by running `send-tx.js` script in `send-tx` directory. Beforehand, you need to change `to` address and `amount` (in quanta) field in `config.json`


```bash
$ cd send-tx
$ npm install
$ node send-tx.js
```

## Log

Log files is available inside `logs` directory in each node.