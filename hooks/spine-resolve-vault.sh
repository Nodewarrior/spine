#!/bin/bash
# Resolve Spine vault path from config chain:
# 1. $SPINE_VAULT_PATH env var
# 2. ~/.spine/config.json vaultPath field
# 3. Default ~/Documents/SpineVault/

if [ -n "$SPINE_VAULT_PATH" ]; then
  echo "$SPINE_VAULT_PATH"
elif [ -f "$HOME/.spine/config.json" ]; then
  # Parse vaultPath from JSON — try python3, then node, then jq
  # Each parser must validate the value is a non-empty string (not null/undefined/empty)
  PARSED=""
  if command -v python3 &>/dev/null; then
    PARSED=$(python3 -c "
import json
v = json.load(open('$HOME/.spine/config.json')).get('vaultPath')
if v and isinstance(v, str) and v.strip(): print(v)
" 2>/dev/null)
  fi
  if [ -z "$PARSED" ] && command -v node &>/dev/null; then
    PARSED=$(node -e "
const v = require('$HOME/.spine/config.json').vaultPath;
if (v && typeof v === 'string' && v.trim()) console.log(v);
" 2>/dev/null)
  fi
  if [ -z "$PARSED" ] && command -v jq &>/dev/null; then
    PARSED=$(jq -r 'if (.vaultPath | type) == "string" and (.vaultPath | length) > 0 then .vaultPath else empty end' "$HOME/.spine/config.json" 2>/dev/null)
  fi
  # Use parsed value if valid, otherwise fall back to default
  if [ -n "$PARSED" ]; then
    echo "$PARSED"
  else
    echo "$HOME/Documents/SpineVault"
  fi
else
  echo "$HOME/Documents/SpineVault"
fi
