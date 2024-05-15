#!/usr/bin/env bash

CHAINID="test"

# App & node has a celestia user with home dir /home/celestia
APP_PATH="/home/celestia/.celestia-app"
NODE_PATH="/home/celestia/bridge/"

# Check if the folder exists
if [ -d "$APP_PATH" ]; then
  # If it exists, delete it
  echo "The folder $APP_PATH exists. Deleting it..."
  rm -rf "$APP_PATH"
  echo "Folder deleted."
else
  # If it doesn't exist, print a message
  echo "The folder $APP_PATH does not exist."
fi

# Build genesis file incl account for passed address
coins="1000000000000000utia"
celestia-appd init $CHAINID --chain-id $CHAINID
celestia-appd keys add validator --keyring-backend="test"
# this won't work because some proto types are declared twice and the logs output to stdout (dependency hell involving iavl)
celestia-appd add-genesis-account $(celestia-appd keys show validator -a --keyring-backend="test") $coins
celestia-appd gentx validator 5000000000utia \
  --keyring-backend="test" \
  --chain-id $CHAINID

celestia-appd collect-gentxs

# Set proper defaults and change ports
# If you encounter: `sed: -I or -i may not be used with stdin` on MacOS you can mitigate by installing gnu-sed
# https://gist.github.com/andre3k1/e3a1a7133fded5de5a9ee99c87c6fa0d?permalink_comment_id=3082272#gistcomment-3082272
sed -i'.bak' 's#"tcp://127.0.0.1:26657"#"tcp://0.0.0.0:26657"#g' ~/.celestia-app/config/config.toml
sed -i'.bak' 's/^timeout_commit\s*=.*/timeout_commit = "2s"/g' ~/.celestia-app/config/config.toml
sed -i'.bak' 's/^timeout_propose\s*=.*/timeout_propose = "2s"/g' ~/.celestia-app/config/config.toml

mkdir -p $NODE_PATH/keys
cp -r $APP_PATH/keyring-test/ $NODE_PATH/keys/keyring-test/

# Start the celestia-app
celestia-appd start --grpc.enable &

# Try to get the genesis hash. Usually first request returns an empty string (port is not open, curl fails), later attempts
# returns "null" if block was not yet produced.
GENESIS=
CNT=0
MAX=30
while [ "${#GENESIS}" -le 4 -a $CNT -ne $MAX ]; do
	GENESIS=$(curl -s http://127.0.0.1:26657/block?height=1 | jq '.result.block_id.hash' | tr -d '"')
	((CNT++))
	sleep 1
done

export CELESTIA_CUSTOM=test:$GENESIS
echo "$CELESTIA_CUSTOM"

celestia bridge init --node.store /home/celestia/bridge
celestia bridge auth write --node.store /home/celestia/bridge > /home/celestia/shared-data/auth-token
tail -n1 /home/celestia/shared-data/auth-token > /home/celestia/shared-data/tmp && cp /home/celestia/shared-data/tmp /home/celestia/shared-data/auth-token && rm /home/celestia/shared-data/tmp && rm /home/celestia/shared-data/tmp
celestia bridge start \
  --node.store $NODE_PATH --gateway \
  --core.ip 127.0.0.1 \
  --keyring.accname validator \
  --gateway.addr 0.0.0.0 \
  --rpc.addr 0.0.0.0 \
