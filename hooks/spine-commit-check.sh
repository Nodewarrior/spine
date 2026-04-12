#!/bin/bash
# Spine Architecture — post-commit hook
# Checks if the latest commit looks significant enough to warrant an Obsidian doc.
# Outputs a suggestion to run /spine-capture if so.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve vault path
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)

# Check if this repo has a folder in the vault
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi
if [ -n "$VAULT_PATH" ] && [ -d "$VAULT_PATH" ] && [ ! -d "$VAULT_PATH/$REPO_NAME" ]; then
  exit 0
fi

# Get the latest commit stats
CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d '[:space:]')
COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null)
INSERTIONS=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
DELETIONS=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

INSERTIONS=${INSERTIONS:-0}
DELETIONS=${DELETIONS:-0}
TOTAL_CHANGES=$((INSERTIONS + DELETIONS))

# Skip trivial commits (less than 20 lines changed or only 1 file)
if [ "$TOTAL_CHANGES" -lt 20 ] && [ "$CHANGED_FILES" -le 1 ]; then
  exit 0
fi

# Skip merge commits
if echo "$COMMIT_MSG" | grep -qiE '^merge'; then
  exit 0
fi

# Skip style/lint/chore commits
if echo "$COMMIT_MSG" | grep -qiE '^(style|lint|chore|docs):'; then
  exit 0
fi

# This looks significant — suggest spine-capture
echo "SPINE: Commit \"$COMMIT_MSG\" changed $CHANGED_FILES files (+$INSERTIONS/-$DELETIONS). Consider running /spine-capture to document this work."
