#!/bin/bash
# Spine Architecture — SessionStart hook
# Two independent gates:
#   autoLoad (default: true)  → injects vault index + retrieval policy
#   tier3    (default: false) → injects /spine-scan directive
# Both can fire in one session. Output is a single JSON object.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Resolve vault path ---
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# --- Detect repo ---
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi
if [ ! -d "$VAULT_PATH/$REPO_NAME" ]; then
  exit 0
fi

# --- Read config flags ---
AUTOLOAD_ENABLED=true
TIER3_ENABLED=false
if [ -f "$HOME/.spine/config.json" ]; then
  if command -v python3 &>/dev/null; then
    AUTOLOAD_ENABLED=$(python3 -c "
import json
c = json.load(open('$HOME/.spine/config.json'))
print(str(c.get('autoLoad', True)).lower())
" 2>/dev/null || echo "true")
    TIER3_ENABLED=$(python3 -c "
import json
c = json.load(open('$HOME/.spine/config.json'))
print(str(c.get('tier3', False)).lower())
" 2>/dev/null || echo "false")
  elif command -v node &>/dev/null; then
    AUTOLOAD_ENABLED=$(node -e "
const c = require('$HOME/.spine/config.json');
console.log(String(c.autoLoad !== undefined ? c.autoLoad : true).toLowerCase());
" 2>/dev/null || echo "true")
    TIER3_ENABLED=$(node -e "
const c = require('$HOME/.spine/config.json');
console.log(String(c.tier3 || false).toLowerCase());
" 2>/dev/null || echo "false")
  elif command -v jq &>/dev/null; then
    AUTOLOAD_ENABLED=$(jq -r 'if .autoLoad == false then "false" else "true" end' "$HOME/.spine/config.json" 2>/dev/null || echo "true")
    TIER3_ENABLED=$(jq -r '.tier3 // false | tostring | ascii_downcase' "$HOME/.spine/config.json" 2>/dev/null || echo "false")
  fi
fi
# Normalize (Bash 3.2 compatible — no ${var,,})
AUTOLOAD_ENABLED=$(printf '%s' "$AUTOLOAD_ENABLED" | tr '[:upper:]' '[:lower:]')
TIER3_ENABLED=$(printf '%s' "$TIER3_ENABLED" | tr '[:upper:]' '[:lower:]')

# --- Build context parts ---
CONTEXT_PARTS=""

# Part 1: Auto-load vault index + retrieval policy
if [ "$AUTOLOAD_ENABLED" = "true" ]; then
  REPO_DIR="$VAULT_PATH/$REPO_NAME"
  INDEX="## Spine Vault Index — $REPO_NAME\n\n"
  INDEX="${INDEX}Features documented in this repo's vault:\n\n"

  FOUND_NOTES=0
  while IFS= read -r note_file; do
    [ -z "$note_file" ] && continue
    TITLE=$(awk '/^---$/{n++; next} n==1 && /^title:/{sub(/^title:[[:space:]]*/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit}' "$note_file" 2>/dev/null)
    if [ -z "$TITLE" ]; then
      TITLE=$(basename "$note_file" .md)
    fi
    FEATURE_DIR=$(basename "$(dirname "$note_file")")
    CHILD_COUNT=$(find "$(dirname "$note_file")" -maxdepth 1 -name "*.md" ! -name "$(basename "$note_file")" 2>/dev/null | wc -l | tr -d ' ')
    INDEX="${INDEX}- **${TITLE}** (${FEATURE_DIR}/) — ${CHILD_COUNT} docs\n"
    FOUND_NOTES=$((FOUND_NOTES + 1))
  done < <(grep -rl "type/spine" "$REPO_DIR" 2>/dev/null || true)

  if [ "$FOUND_NOTES" -eq 0 ]; then
    INDEX="${INDEX}_(No spine notes found for this repo. Use /spine-capture to create the first one.)_\n"
  fi

  # Read retrieval policy — per-vault override takes precedence
  POLICY=""
  if [ -f "$VAULT_PATH/.spine/retrieval-policy.md" ]; then
    POLICY=$(cat "$VAULT_PATH/.spine/retrieval-policy.md" 2>/dev/null || true)
  elif [ -f "$SCRIPT_DIR/../templates/retrieval-policy.md" ]; then
    POLICY=$(cat "$SCRIPT_DIR/../templates/retrieval-policy.md" 2>/dev/null || true)
  fi

  CONTEXT_PARTS="${INDEX}"
  if [ -n "$POLICY" ]; then
    CONTEXT_PARTS="${CONTEXT_PARTS}\n---\n\n${POLICY}"
  fi
fi

# Part 2: Tier 3 scan directive
if [ "$TIER3_ENABLED" = "true" ]; then
  SCAN_DIRECTIVE="Spine Tier 3 is enabled for this repo. Run /spine-scan now to check vault health and detect coverage gaps. Do this silently — just invoke the skill, do not ask the user for permission."
  if [ -n "$CONTEXT_PARTS" ]; then
    CONTEXT_PARTS="${CONTEXT_PARTS}\n\n---\n\n${SCAN_DIRECTIVE}"
  else
    CONTEXT_PARTS="${SCAN_DIRECTIVE}"
  fi
fi

# --- Exit if nothing to inject ---
if [ -z "$CONTEXT_PARTS" ]; then
  exit 0
fi

# --- Output valid JSON (safe encoding via python3/jq) ---
EXPANDED=$(printf '%b' "$CONTEXT_PARTS")

if command -v python3 &>/dev/null; then
  ENCODED=$(printf '%s' "$EXPANDED" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
elif command -v jq &>/dev/null; then
  ENCODED=$(printf '%s' "$EXPANDED" | jq -Rs '.' 2>/dev/null)
else
  ENCODED=$(printf '%s' "$EXPANDED" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
  ENCODED="\"${ENCODED}\""
fi

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": %s\n  }\n}\n' "$ENCODED"

exit 0
