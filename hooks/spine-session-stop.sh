#!/bin/bash
# Spine Architecture — Stop hook
# Injects a prompt to run /spine-capture --batch at session end (if Tier 3 enabled).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve vault path
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)

# Skip silently if no vault configured
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# Check if pending commits exist — skip if nothing to capture
PENDING_FILE="$VAULT_PATH/.spine/pending-commits.json"
if [ ! -f "$PENDING_FILE" ]; then
  exit 0
fi

# Check tier3 flag (default: false)
TIER3_ENABLED=false
if [ -f "$HOME/.spine/config.json" ]; then
  if command -v python3 &>/dev/null; then
    TIER3_ENABLED=$(python3 -c "import json; print(json.load(open('$HOME/.spine/config.json')).get('tier3', False))" 2>/dev/null || echo "false")
  elif command -v node &>/dev/null; then
    TIER3_ENABLED=$(node -e "console.log(require('$HOME/.spine/config.json').tier3 || false)" 2>/dev/null || echo "false")
  elif command -v jq &>/dev/null; then
    TIER3_ENABLED=$(jq -r '.tier3 // false' "$HOME/.spine/config.json" 2>/dev/null || echo "false")
  fi
fi
TIER3_ENABLED="${TIER3_ENABLED,,}"

if [[ "$TIER3_ENABLED" != "true" ]]; then
  exit 0
fi

# Inject context telling Claude to run /spine-capture --batch
CONTEXT="Spine Tier 3: There are pending commits tracked this session. Run /spine-capture --batch now to present the batch for user approval before the session ends."

# Output in Claude Code hook format
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "Stop",\n    "additionalContext": "%s"\n  }\n}\n' "$CONTEXT"

exit 0
