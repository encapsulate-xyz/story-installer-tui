#!/bin/bash

# Variables (centralized configuration)
GO_VERSION="1.23.1"
GO_BINARY_URL="https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz"
GETH_BINARY_URL="https://github.com/piplabs/story-geth/releases/download/v0.9.4/geth-linux-amd64"
STORY_BINARY_URL="https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz"

# Snapshot URLs
ARCHIVAL_GETH_SNAPSHOT="https://snapshot.encapsulate.xyz/story/archive/story_geth_snapshot_archive.lz4"
ARCHIVAL_STORY_SNAPSHOT="https://snapshot.encapsulate.xyz/story/archive/story_snapshot_archive.lz4"
PRUNED_GETH_SNAPSHOT="https://snapshot.encapsulate.xyz/story/pruned/story_geth_snapshot_pruned.lz4"
PRUNED_STORY_SNAPSHOT="https://snapshot.encapsulate.xyz/story/pruned/story_snapshot_pruned.lz4"
ADDRBOOK_URL="https://snapshot.encapsulate.xyz/story/addrbook.json"

# Seeds and Enode
SEEDS="5a0191a6bd8f17c9d2fa52386ff409f5d796d112@b1.testnet.storyrpc.io:26656,0e2f0d4b5204e5e92a994a1eaa745b9ccb1d747b@b2.testnet.storyrpc.io:26656"
ENODE="enode://dd2441549175771ee0393ddbeaa58172270c184b2a46bcdeba0513bc3e589e42cdb4dfc147c6ad6f837a9c4e1c477428a2df80f6d4dd61d8f3c891ab2a273899@152.53.102.226:30303"

# RPC Endpoint
RPC_ENDPOINT="https://testnet.storyrpc.io"

# System services
STORY_SERVICE="story"
GETH_SERVICE="story-geth"

# Colors
RED="\033[31m"
YELLOW="\033[33m"
GREEN="\033[32m"
NORMAL="\033[0m"

# Function: Exit handler
function exit_script {
  echo -e "$YELLOW Exiting...$NORMAL"
  exit 1
}

# Function: check sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo" 
   exit 1
fi

# Function: Install dependencies
function install_dependencies() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip aria2 -y
}

# Function: Download and extract binaries
function download_binaries {
  echo -e "$GREEN Downloading binaries...$NORMAL"
  wget $STORY_BINARY_URL -O story-binary.tar.gz
  tar -xzvf story-binary.tar.gz && sudo mv story-linux-amd64-0.11.0-aac4bfe/story /usr/local/bin/
  wget $GETH_BINARY_URL -O geth-linux-amd64 && chmod +x geth-linux-amd64
  sudo mv geth-linux-amd64 /usr/local/bin/story-geth
  echo -e "$GREEN Binaries updated and services restarted.$NORMAL"
}

# Function: Initialize Node
function initialize_node {
  read -p "Enter the node name (MONIKER): " MONIKER
  /usr/local/bin/story init --moniker $MONIKER --network iliad
}

# Function: Create systemd service files
function create_services {
  echo -e "$GREEN Creating service files...$NORMAL"
  sudo tee /etc/systemd/system/${GETH_SERVICE}.service <<EOF
[Unit]
Description=Geth Node Service
After=network.target

[Service]
ExecStart=/usr/local/bin/story-geth --iliad --syncmode full
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  sudo tee /etc/systemd/system/${STORY_SERVICE}.service <<EOF
[Unit]
Description=Story Node Service
After=network.target

[Service]
ExecStart=/usr/local/bin/story run
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable ${GETH_SERVICE}
  sudo systemctl enable ${STORY_SERVICE}
}

# Function: Stop services
function stop_services {
  echo -e "$YELLOW Stopping node services...$NORMAL"
  sudo systemctl stop $STORY_SERVICE $GETH_SERVICE
}

# Function: Restart services
function restart_services {
  echo -e "$GREEN Restarting node services...$NORMAL"
  sudo systemctl restart $STORY_SERVICE $GETH_SERVICE
}

# Function: Download snapshots
function download_snapshot {
  if [ "$SNAPSHOT" == "archival" ]; then
    echo -e "$GREEN Downloading archival snapshots...$NORMAL"
    wget $ARCHIVAL_GETH_SNAPSHOT -O geth_snapshot.lz4
    wget $ARCHIVAL_STORY_SNAPSHOT -O story_snapshot.lz4
  else
    echo -e "$GREEN Downloading pruned snapshots...$NORMAL"
    wget $PRUNED_GETH_SNAPSHOT -O geth_snapshot.lz4
    wget $PRUNED_STORY_SNAPSHOT -O story_snapshot.lz4
  fi
}

# Function: Extract snapshots and delete
function extract_snapshot {
  echo -e "$GREEN Extracting snapshots...$NORMAL"
  lz4 -d geth_snapshot.lz4 | tar -C ~/.story/geth/iliad/geth -xv
  lz4 -d story_snapshot.lz4 | tar -C ~/.story/story -xv

  echo -e "$GREEN Removing snapshots...$NORMAL"
  rm -rf geth_snapshot.lz4 story_snapshot.lz4
}

# Main menu using whiptail
OPTION=$(whiptail --title "Node Setup Menu" --menu "Select an option:" 20 78 11 \
"1" "Install Node Environment" \
"2" "Apply Blockchain Snapshot" \
"3" "Update Binary" \
"4" "Check Node Status" \
"5" "View Logs" \
"6" "Add Seed Nodes" \
"7" "Add Peer Nodes" \
"8" "Add Geth Enode" \
"9" "Download Addrbook" \
"10" "Stop Services" \
"11" "Restart Services" 3>&1 1>&2 2>&3)

if [ $? != 0 ]; then exit_script; fi

case $OPTION in
1)
  if whiptail --yesno "Proceed with node installation? This will override existing data." 10 60; then
    echo -e "$GREEN Installing dependencies...$NORMAL"
    install_dependencies
    download_binaries
    initialize_node
    create_services
    restart_services
    echo -e "$GREEN Installation complete!$NORMAL"
  fi
  ;;
2)
  SNAPSHOT=$(whiptail --title "Snapshot Selection" --menu \
    "Choose snapshot type:" 15 60 2 \
    "archival" "Full blockchain history (large)" \
    "pruned" "Lightweight snapshot" 3>&1 1>&2 2>&3)

  if [ $? != 0 ]; then exit_script; fi
  stop_services
  download_snapshot

  # Backup priv_validator_state.json
  echo -e "$GREEN Backing up priv_validator_state.json...$NORMAL"
  cp ~/.story/story/data/priv_validator_state.json ~/.story/story/priv_validator_state.json.backup

  # Remove old data
  echo -e "$GREEN Removing old data...$NORMAL"
  rm -rf ~/.story/story/data
  rm -rf ~/.story/geth/iliad/geth/chaindata

  extract_snapshot

  # Restore priv_validator_state.json
  echo -e "$GREEN Extracting snapshots...$NORMAL"
  mv ~/.story/story/priv_validator_state.json.backup ~/.story/story/data/priv_validator_state.json

  restart_services

   echo -e "$GREEN Snapshot sync completed successfully.$NORMAL"
  ;;
3)
  BINARY=$(whiptail --menu "Select binary to update:" 15 60 2 \
    "story" "Update Story binary" \
    "geth" "Update Geth binary" 3>&1 1>&2 2>&3)
  
  if [ $? != 0 ]; then exit_script; fi

  stop_services

  if [ "$BINARY" == "story" ]; then
    echo -e "$GREEN Updating Story binary...$NORMAL"
    wget $STORY_BINARY_URL -O story-binary.tar.gz
    tar -xzvf story-binary.tar.gz && sudo mv story-linux-amd64-0.11.0-aac4bfe/story /usr/local/bin/
  elif [ "$BINARY" == "geth" ]; then
    echo -e "$GREEN Updating Geth binary...$NORMAL"
    wget $GETH_BINARY_URL -O geth-linux-amd64 && chmod +x geth-linux-amd64
    sudo mv geth-linux-amd64 /usr/local/bin/story-geth
  fi

  restart_services
  ;;
4)
  echo -e "$GREEN Monitoring node status...$NORMAL"
  while true; do
    YOUR_BLOCK=$(curl -s localhost:26657/status | jq -r '.result.sync_info.latest_block_height')
    RPC_BLOCK=$(curl -s $RPC_ENDPOINT/status | jq -r '.result.sync_info.latest_block_height')
    LAG=$((RPC_BLOCK - YOUR_BLOCK))
    echo -e "$GREEN Your Block: $YOUR_BLOCK | RPC Block: $RPC_BLOCK | Lag: $LAG blocks$NORMAL"
    sleep 5
  done
  ;;
5)
  LOG=$(whiptail --menu "Select logs to view:" 15 60 2 \
    "${STORY_SERVICE}" "View Story logs" \
    "${GETH_SERVICE}" "View Geth logs" 3>&1 1>&2 2>&3)

  if [ $? != 0 ]; then exit_script; fi

  sudo journalctl -u ${LOG} -f
  ;;
6)
  sed -i "s/^seeds *=.*/seeds = \"$SEEDS\"/" ~/.story/story/config/config.toml
  restart_services
  ;;
7)
  PEERS=$(curl -s ${RPC_ENDPOINT}/net_info | jq -r '.result.peers[] | .remote_ip' | paste -sd,)
  sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" ~/.story/story/config/config.toml
  restart_services
  ;;
8)
  story-geth attach ~/.story/geth/iliad/geth.ipc --exec "admin.addPeer('$ENODE')"
  ;;
9)
  wget -O ~/.story/story/config/addrbook.json $ADDRBOOK_URL
  restart_services
  ;;
10)
  stop_services
  ;;
11)
  restart_services
  ;;
*)
  exit_script
  ;;
esac