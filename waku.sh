#!/bin/bash

# Define paths
COMPOSE_DIR="$HOME/nwaku-compose"
ENV_PATH="$COMPOSE_DIR/.env"
COMPOSE_PATH="$COMPOSE_DIR/docker-compose.yml"
BACKUP_DIR="$HOME/backup_nwaku"

# Functions

function stop_node {
  echo "⛔ Stopping Waku node..."
  docker compose -f "$COMPOSE_PATH" down
}

function start_node {
  echo "▶️ Starting Waku node..."
  docker compose -f "$COMPOSE_PATH" up -d
}

function check_logs {
  echo "📜 Showing last 100 log lines..."
  docker compose -f "$COMPOSE_PATH" logs -f --tail=100
}

function update_node {
  echo "🔄 Updating Waku node..."

  cd "$COMPOSE_DIR"

  stop_node

  # Backup keystore
  if [ ! -f "$BACKUP_DIR/keystore.json" ]; then
    mkdir -p "$BACKUP_DIR"
    cp keystore/keystore.json "$BACKUP_DIR/keystore.json"
  fi

  # Clean old data
  rm -rf keystore rln_tree

  # Git update (safe with stash)
  git fetch
  if [ -n "$(git status --porcelain)" ]; then
    echo "📦 Local changes detected, stashing..."
    git stash -u
    git merge origin/master
    git stash pop
  else
    git merge origin/master
  fi

  # Replace .env with default
  rm -f "$ENV_PATH" && cp .env.example "$ENV_PATH"

  # Prompt for user input
  [ -z "$RPC" ] && read -p "Enter RPC : " RPC
  [ -z "$EPK" ] && read -p "Enter EVM private key : " EPK
  [ -z "$PASS" ] && read -p "Enter password : " PASS

  # Update .env
  sed -i -e "s%RLN_RELAY_ETH_CLIENT_ADDRESS=.*%RLN_RELAY_ETH_CLIENT_ADDRESS=${RPC}%g" "$ENV_PATH"
  sed -i -e "s%ETH_TESTNET_KEY=.*%ETH_TESTNET_KEY=${EPK}%g" "$ENV_PATH"
  sed -i -e "s%RLN_RELAY_CRED_PASSWORD=.*%RLN_RELAY_CRED_PASSWORD=${PASS}%g" "$ENV_PATH"
  sed -i -e "s%STORAGE_SIZE=.*%STORAGE_SIZE=50GB%g" "$ENV_PATH"
  sed -i -e "s%NWAKU_IMAGE=.*%NWAKU_IMAGE=wakuorg/nwaku:v0.35.1%g" "$ENV_PATH"
  grep -q '^POSTGRES_SHM=' "$ENV_PATH" || echo 'POSTGRES_SHM=4g' >> "$ENV_PATH"

  # Update ports
  sed -i 's/0\.0\.0\.0:3000:3000/0.0.0.0:3003:3000/g' "$COMPOSE_PATH"
  sed -i 's/8000:8000/8004:8000/g' "$COMPOSE_PATH"
  sed -i 's/80:80/81:80/g' "$COMPOSE_PATH"
  sed -i 's/127.0.0.1:8003:8003/127.0.0.1:8005:8003/g' "$COMPOSE_PATH"

  # Register RLN and restart node
  bash "$COMPOSE_DIR/register_rln.sh"
  sleep 2
  start_node

  echo "✅ Update complete!"
}

function uninstall_node {
  echo "🧹 Uninstalling Waku node..."
  stop_node
  rm -rf "$COMPOSE_DIR"
  echo "✅ Node removed, backup preserved in $BACKUP_DIR"
}

function exit_script {
  echo "👋 Exiting. Bye!"
  exit 0
}

# Menu loop
while true; do
  echo ""
  echo "🔧 Waku Node Manager — Choose an option:"
  select choice in \
    "Stop Waku node" \
    "Start Waku node" \
    "Check Waku logs" \
    "Update Waku node" \
    "Uninstall Waku node" \
    "Exit script"; do

    case $REPLY in
      1) stop_node ;;
      2) start_node ;;
      3) check_logs ;;
      4) update_node ;;
      5) uninstall_node ;;
      6) exit_script ;;
      *) echo "❌ Invalid option";;
    esac

    break
  done
done