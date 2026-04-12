#!/bin/bash
# Resolve Spine vault path from config chain:
# 1. $SPINE_VAULT_PATH env var
# 2. ~/.spine/config.json vaultPath field
# 3. Default ~/Documents/SpineVault/

if [ -n "$SPINE_VAULT_PATH" ]; then
  echo "$SPINE_VAULT_PATH"
elif [ -f "$HOME/.spine/config.json" ]; then
  # Parse vaultPath from JSON — try python3, then node, then jq
  if command -v python3 &>/dev/null; then
    python3 -c "import json; print(json.load(open('$HOME/.spine/config.json'))['vaultPath'])" 2>/dev/null && exit 0
  fi
  if command -v node &>/dev/null; then
    node -e "console.log(require('$HOME/.spine/config.json').vaultPath)" 2>/dev/null && exit 0
  fi
  if command -v jq &>/dev/null; then
    jq -r '.vaultPath' "$HOME/.spine/config.json" 2>/dev/null && exit 0
  fi
  # Fallback if parsing fails
  echo "$HOME/Documents/SpineVault"
else
  echo "$HOME/Documents/SpineVault"
fi
