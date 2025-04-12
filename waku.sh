#!/bin/bash

# Define paths
COMPOSE_DIR="$HOME/nwaku-compose"
ENV_PATH="$COMPOSE_DIR/.env"
COMPOSE_PATH="$COMPOSE_DIR/docker-compose.yml"
BACKUP_DIR="$HOME/backup_nwaku"

cd "$COMPOSE_DIR"

# Stop containers and create keystore backup if not already exists
docker compose down

if [ ! -f "$BACKUP_DIR/keystore.json" ]; then
  mkdir -p "$BACKUP_DIR"
  cp keystore/keystore.json "$BACKUP_DIR/keystore.json"
fi

# Remove old keystore and rln_tree data
rm -rf keystore rln_tree

# Safely update the repository
git fetch

if [ -n "$(git status --porcelain)" ]; then
  echo "Local changes detected, temporarily stashing them..."
  git stash -u
  git merge origin/master
  git stash pop
else
  git merge origin/master
fi

# Replace .env file with the default template
rm -f "$ENV_PATH" && cp .env.example "$ENV_PATH"

# Prompt for required variables if not set
[ -z "$RPC" ] && read -p "Enter RPC : " RPC
[ -z "$EPK" ] && read -p "Enter EVM private key : " EPK
[ -z "$PASS" ] && read -p "Enter password : " PASS

# Insert updated values into .env
sed -i -e "s%RLN_RELAY_ETH_CLIENT_ADDRESS=.*%RLN_RELAY_ETH_CLIENT_ADDRESS=${RPC}%g" "$ENV_PATH"
sed -i -e "s%ETH_TESTNET_KEY=.*%ETH_TESTNET_KEY=${EPK}%g" "$ENV_PATH"
sed -i -e "s%RLN_RELAY_CRED_PASSWORD=.*%RLN_RELAY_CRED_PASSWORD=${PASS}%g" "$ENV_PATH"
sed -i -e "s%STORAGE_SIZE=.*%STORAGE_SIZE=50GB%g" "$ENV_PATH"
sed -i -e "s%NWAKU_IMAGE=.*%NWAKU_IMAGE=wakuorg/nwaku:v0.35.1%g" "$ENV_PATH"
grep -q '^POSTGRES_SHM=' "$ENV_PATH" || echo 'POSTGRES_SHM=4g' >> "$ENV_PATH"

# Change exposed ports in docker-compose.yml to avoid conflicts
sed -i 's/0\.0\.0\.0:3000:3000/0.0.0.0:3003:3000/g' "$COMPOSE_PATH"
sed -i 's/8000:8000/8004:8000/g' "$COMPOSE_PATH"
sed -i 's/80:80/81:80/g' "$COMPOSE_PATH"
sed -i 's/127.0.0.1:8003:8003/127.0.0.1:8005:8003/g' "$COMPOSE_PATH"

# Run RLN registration script and start containers
bash "$COMPOSE_DIR/register_rln.sh"
sleep 2
docker compose -f "$COMPOSE_PATH" up -d