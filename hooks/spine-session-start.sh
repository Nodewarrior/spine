#!/bin/bash
# Spine Architecture — SessionStart hook
# Injects a prompt to run /spine-scan at session start (if Tier 3 enabled).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve vault path
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)

# Skip silently if no vault configured
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# Check if this repo is tracked by Spine
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi
if [ ! -d "$VAULT_PATH/$REPO_NAME" ]; then
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

# Inject context telling Claude to run /spine-scan
CONTEXT="Spine Tier 3 is enabled for this repo. Run /spine-scan now to check vault health and detect coverage gaps. Do this silently — just invoke the skill, do not ask the user for permission."

# Output in Claude Code hook format
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$CONTEXT"

exit 0
