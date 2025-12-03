#!/bin/bash

set -exu
set -o pipefail

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq first."
    exit 1
fi
# Check if hexseed-from-address is installed
if ! command -v hexseed-from-address &> /dev/null; then
    echo "Error: hexseed-from-address is not installed. Please install hexseed-from-address first."
    exit 1
fi

trap 'echo "Error on line $LINENO"; exit 1' ERR

current_dir=$(pwd)

#only change these variables
NUM_NODES=3
BOOT_DIR=$current_dir/zond-testnet-boot

rm genesis.ssz || echo "No such file"
rm boot.key || echo "No such file"
rm -rf zond-testnet-*/ || echo "No such directory"

mkdir -p $BOOT_DIR/logs

./bin/bootnode -genkey boot.key

GZOND_BOOTNODE_PORT=30301

GZOND_HTTP_PORT=8000
GZOND_WS_PORT=8100
GZOND_AUTH_RPC_PORT=8200
GZOND_PPROF_PORT=8300
GZOND_METRICS_PORT=8400
GZOND_NETWORK_PORT=8500

QRYSM_BEACON_RPC_PORT=4000
QRYSM_BEACON_GRPC_GATEWAY_PORT=4100
QRYSM_BEACON_P2P_TCP_PORT=4200
QRYSM_BEACON_P2P_UDP_PORT=4300
QRYSM_BEACON_MONITORING_PORT=4400
QRYSM_BEACON_PPROF_PORT=4500

QRYSM_VALIDATOR_RPC_PORT=7000
QRYSM_VALIDATOR_GRPC_GATEWAY_PORT=7100
QRYSM_VALIDATOR_MONITORING_PORT=7200

printf "%s" "$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' ')" > $BOOT_DIR/password.txt
password=$(cat $BOOT_DIR/password.txt)
chmod 600 $BOOT_DIR/password.txt

#create validator keys
./bin/deposit new-seed --num-validators=$NUM_NODES --keystore-password-file=$BOOT_DIR/password.txt --validator-start-index=0 --folder=$BOOT_DIR/validator_keys/

DEPOSIT_FILE=$(ls $BOOT_DIR/validator_keys/deposit*)
chmod 600 $BOOT_DIR/validator_keys/keystore*

#create prefunded address
./bin/gzond account new --datadir=$BOOT_DIR/gzonddata/ --password=$BOOT_DIR/password.txt
zond_address=$(./bin/gzond account list --datadir=$BOOT_DIR/gzonddata/ | awk '{gsub(/[{}]/,"",$3); print $3}')
jq --arg new "$zond_address" '
  (.alloc | keys[0]) as $first |
  .alloc |= with_entries(
    if .key == $first then
      {key: $new, value: .value}
    else
      .
    end
  )
' genesis.json > genesis.tmp && mv genesis.tmp genesis.json

result="0x$(hexseed-from-address -p "$password" -a "0x${zond_address:1}" -d $BOOT_DIR/gzonddata/ | grep -i hexseed | awk '{print $2}')"
jq --arg seed "$result" '.hexseed = $seed' send-tx/config.json > tmp.config.json && mv tmp.config.json send-tx/config.json

#generate genesis file
./bin/qrysmctl testnet generate-genesis --output-ssz=./genesis.ssz --chain-config-file=./config.yml --gzond-genesis-json-in=genesis.json --gzond-genesis-json-out=genesis.json --genesis-time-delay=30 --deposit-json-file="$DEPOSIT_FILE" --num-validators=$NUM_NODES

#start el bootnode
EXTIP=127.0.0.1
ENODE_PUBKEY=$(./bin/bootnode --nodekey=boot.key -writeaddress)
nohup ./bin/bootnode --nodekey=boot.key -addr=$EXTIP:$GZOND_BOOTNODE_PORT -verbosity 5 > $BOOT_DIR/logs/bootnode.log 2>&1 &

sleep 0.5

#start cl bootnode
nohup ./bin/beacon-chain --datadir=$BOOT_DIR/beacondata --min-sync-peers=0  --bootstrap-node=  --execution-endpoint=   --accept-terms-of-use   --jwt-secret=  --verbosity info --disable-monitoring --disable-grpc-gateway --disable-aggregate-parallel --disable-grpc-connection-logging --disable-optional-engine-methods --disable-staking-contract-check --checkpoint-sync-url= --genesis-state=genesis.ssz --chain-config-file=config.yml   --config-file=config.yml   --chain-id=7070 --p2p-max-peers=1000 --p2p-tcp-port=$QRYSM_BEACON_P2P_TCP_PORT --p2p-udp-port=$QRYSM_BEACON_P2P_UDP_PORT --rpc-port=$QRYSM_BEACON_RPC_PORT > $BOOT_DIR/logs/beacon.log 2>&1 &

sleep 0.5

ENODE="enode://${ENODE_PUBKEY}@$EXTIP:0?discport=$GZOND_BOOTNODE_PORT"
ENR=$(grep -i "enr" $BOOT_DIR/logs/beacon.log | sed -n 's/.*ENR="\([^"]*\)".*/\1/p' | tr -d '\n')

for (( i=1; i<=$NUM_NODES; i++ )); do
    NODE_DIR=zond-testnet-$i

    rm -rf "$NODE_DIR"

    mkdir -p "$NODE_DIR"/gzonddata
    mkdir -p "$NODE_DIR"/beacondata
    mkdir -p "$NODE_DIR"/validator_keys
    mkdir -p "$NODE_DIR"/logs

    ./bin/beacon-chain generate-auth-secret --output-file="$NODE_DIR"/jwt.hex
    chmod 400 "$NODE_DIR"/jwt.hex

    cp $BOOT_DIR/password.txt "$NODE_DIR"/password.txt
    chmod 600 "$NODE_DIR"/password.txt

    file=$(ls $BOOT_DIR/validator_keys/*_238_$((i-1))*)
    cp $file "$NODE_DIR"/validator_keys
    chmod 600 "$NODE_DIR"/validator_keys/keystore*

    #create wallet
    ./bin/validator wallet create --wallet-dir=""$NODE_DIR""/validator_keys/ --keymanager-kind=imported --wallet-password-file=""$NODE_DIR""/password.txt --accept-terms-of-use

    #import validator keys
    ./bin/validator accounts import --wallet-dir=""$NODE_DIR""/validator_keys/ --keys-dir=""$NODE_DIR""/validator_keys/ --wallet-password-file=""$NODE_DIR""/password.txt --account-password-file=""$NODE_DIR""/password.txt --accept-terms-of-use

    ./bin/gzond init --datadir $NODE_DIR/gzonddata genesis.json

    #start gzond
    provider=$(echo "http://localhost:$((GZOND_HTTP_PORT + i))")
    if [ "$i" -eq 1 ]; then
      jq --arg seed "$provider" '.provider = $seed' send-tx/config.json > tmp.config.json && mv tmp.config.json send-tx/config.json
    fi
    nohup ./bin/gzond   --nat=extip:0.0.0.0 --networkid=7070   --http   --http.api "web3,zond,net"   --datadir="$NODE_DIR"/gzonddata --syncmode=full   --snapshot=false --authrpc.jwtsecret="$NODE_DIR"/jwt.hex --bootnodes="$ENODE" --authrpc.port=$((GZOND_AUTH_RPC_PORT + i)) --http.port=$((GZOND_HTTP_PORT + i)) --ws.port=$((GZOND_WS_PORT + i)) --discovery.port=$((GZOND_NETWORK_PORT + i)) --port=$((GZOND_NETWORK_PORT + i)) --pprof.port=$((GZOND_PPROF_PORT + i)) --metrics.port=$((GZOND_METRICS_PORT + i)) > "$NODE_DIR"/logs/gzond.log 2>&1 &

    sleep 0.5

    #start beacon-chain
    nohup ./bin/beacon-chain   --datadir="$NODE_DIR"/beacondata --min-sync-peers=0   --genesis-state=genesis.ssz  --chain-config-file=config.yml   --config-file=config.yml   --chain-id=7070   --execution-endpoint="http://localhost:$((GZOND_AUTH_RPC_PORT + i))"   --accept-terms-of-use   --jwt-secret="$NODE_DIR"/jwt.hex  --contract-deployment-block=0   --verbosity info --suggested-fee-recipient=Z20e526833d2ab5bd20de64cc00f2c2c7a07060bf --monitoring-port=$((QRYSM_BEACON_MONITORING_PORT + i)) --p2p-tcp-port=$((QRYSM_BEACON_P2P_TCP_PORT + i)) --p2p-udp-port=$((QRYSM_BEACON_P2P_UDP_PORT + i)) --rpc-port=$((QRYSM_BEACON_RPC_PORT + i)) --grpc-gateway-port=$((QRYSM_BEACON_GRPC_GATEWAY_PORT + i)) --pprofport=$((QRYSM_BEACON_PPROF_PORT + i)) --bootstrap-node="$ENR" > "$NODE_DIR"/logs/beacon.log 2>&1 &

    sleep 0.5

    #start validator
    nohup ./bin/validator     --accept-terms-of-use=true      --chain-config-file=config.yml     --wallet-dir="$NODE_DIR"/validator_keys/      --wallet-password-file="$NODE_DIR"/password.txt     --disable-monitoring=false --verbosity info --suggested-fee-recipient=Z20e526833d2ab5bd20de64cc00f2c2c7a07060bf --graffiti="zond-qrysm-testnet" --beacon-rest-api-provider="http://127.0.0.1:$((QRYSM_BEACON_GRPC_GATEWAY_PORT + i))" --beacon-rpc-gateway-provider="127.0.0.1:$((QRYSM_BEACON_GRPC_GATEWAY_PORT + i))" --beacon-rpc-provider="127.0.0.1:$((QRYSM_BEACON_RPC_PORT + i))" --monitoring-port=$((QRYSM_VALIDATOR_MONITORING_PORT + i))  > "$NODE_DIR"/logs/validator.log 2>&1 &  
done







