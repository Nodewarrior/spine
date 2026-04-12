#!/bin/bash
# Spine Architecture — status line segment
# Shows vault activity with a bone avatar.
#
# Usage: Add this to your existing status line command, or use standalone.
# In ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "bash /path/to/statusline-spine.sh"
#   }
#
# Output examples:
#   🦴 16         (grey — vault quiet, no changes today)
#   🦴 3↑/16      (green — 3 docs modified today out of 16 total)

# Read stdin (Claude Code passes JSON context)
input=$(cat)

# ANSI colors
green=$'\033[38;5;114m'
grey=$'\033[38;5;244m'
bold=$'\033[1m'
reset=$'\033[0m'

# Resolve vault path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$SPINE_VAULT_PATH" ]; then
  VAULT="$SPINE_VAULT_PATH"
elif [ -f "$HOME/.spine/config.json" ]; then
  VAULT=$(python3 -c "import json; print(json.load(open('$HOME/.spine/config.json'))['vaultPath'])" 2>/dev/null)
fi
VAULT="${VAULT:-$HOME/Documents/SpineVault}"

if [ ! -d "$VAULT" ]; then
  exit 0
fi

# Find repo folders (directories that contain feature subdirectories with .md files)
repo_dirs=""
for dir in "$VAULT"/*/; do
  [ -d "$dir" ] && repo_dirs="$repo_dirs $dir"
done

if [ -z "$repo_dirs" ]; then
  exit 0
fi

# Count docs modified today (only inside repo folders)
today=$(date +%Y-%m-%d)
recent_docs=$(find $repo_dirs -name "*.md" -newermt "$today" 2>/dev/null | wc -l | tr -d '[:space:]')
recent_docs=${recent_docs:-0}

# Count total spine docs (inside repo folders)
total_spines=$(find $repo_dirs -name "*.md" 2>/dev/null | wc -l | tr -d '[:space:]')
total_spines=${total_spines:-0}

# Add Spine Architecture.md if it exists
if [ -f "$VAULT/Spine Architecture.md" ]; then
  total_spines=$((total_spines + 1))
  if [ "$VAULT/Spine Architecture.md" -nt "$today" ] 2>/dev/null; then
    recent_docs=$((recent_docs + 1))
  fi
fi

if [ "$recent_docs" -gt 0 ]; then
  printf " %s🦴 %s%s↑%s%s/%s%s" "$green" "$bold" "$recent_docs" "$reset" "$grey" "$total_spines" "$reset"
else
  printf " %s🦴 %s%s" "$grey" "$total_spines" "$reset"
fi
