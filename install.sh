#!/usr/bin/env bash
set -e

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="quickup"
TMP_FILE="$(mktemp)"
RAW_URL="https://raw.githubusercontent.com/RookiePlayers/Quickup/main/setup_workspace.sh"

echo "[Quickup] 🚀 Installing workspace setup script..."

# Detect WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "[Quickup] 🧩 Detected Windows Subsystem for Linux (WSL)"
  WSL=true
else
  WSL=false
fi

# Download the main script
curl -fsSL -o "$TMP_FILE" "$RAW_URL"
chmod +x "$TMP_FILE"

sudo mv "$TMP_FILE" "$INSTALL_DIR/$SCRIPT_NAME"
echo "[Quickup] ✅ Installed to $INSTALL_DIR/$SCRIPT_NAME"

# Docker sanity check
if ! command -v docker >/dev/null 2>&1; then
  echo "[Quickup] ⚠️ Docker not found."
  if [ "$WSL" = true ]; then
    echo "[Quickup] 💡 On WSL, install Docker Desktop for Windows and enable 'Use WSL 2 based engine'."
    echo "Download: https://www.docker.com/products/docker-desktop/"
  else
    echo "[Quickup] 💡 Install Docker manually: https://docs.docker.com/engine/install/"
  fi
else
  echo "[Quickup] 🐳 Docker found: $(docker --version)"
fi

echo
echo "[Quickup] All done! Run it with:"
echo "  quickup"