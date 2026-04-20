#!/bin/bash
# Spine Architecture — post-commit hook
# Silently records significant commits to {vault}/.spine/pending-commits.json.
# No output is ever produced. Exits 0 always.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve vault path
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)

# Exit silently if no vault configured or vault dir doesn't exist
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# Detect repo name from git remote; fall back to directory name
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi

# Exit silently if repo folder doesn't exist in vault
if [ ! -d "$VAULT_PATH/$REPO_NAME" ]; then
  exit 0
fi

# Gather commit stats
COMMIT_HASH=$(git log -1 --pretty=%h 2>/dev/null)
COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null)
COMMIT_TIMESTAMP=$(git log -1 --pretty=%aI 2>/dev/null)
FILES_CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null)
CHANGED_FILES_COUNT=$(echo "$FILES_CHANGED" | grep -c . 2>/dev/null || echo 0)
INSERTIONS=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
DELETIONS=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

INSERTIONS=${INSERTIONS:-0}
DELETIONS=${DELETIONS:-0}
TOTAL_CHANGES=$((INSERTIONS + DELETIONS))

# Skip trivial commits (less than 20 lines changed AND only 1 file)
if [ "$TOTAL_CHANGES" -lt 20 ] && [ "$CHANGED_FILES_COUNT" -le 1 ]; then
  exit 0
fi

# Skip merge commits
if echo "$COMMIT_MSG" | grep -qiE '^merge'; then
  exit 0
fi

# Skip style/lint/chore/docs commits
if echo "$COMMIT_MSG" | grep -qiE '^(style|lint|chore|docs):'; then
  exit 0
fi

# Ensure .spine directory exists in vault
mkdir -p "$VAULT_PATH/.spine" 2>/dev/null

PENDING_FILE="$VAULT_PATH/.spine/pending-commits.json"

# Build the new commit entry and append it to pending-commits.json.
# Try python3 first, then node, then jq, then fallback to fresh file.
if command -v python3 &>/dev/null; then
  python3 - "$PENDING_FILE" "$COMMIT_HASH" "$COMMIT_MSG" "$COMMIT_TIMESTAMP" "$REPO_NAME" \
    "$INSERTIONS" "$DELETIONS" "$FILES_CHANGED" <<'PYEOF' 2>/dev/null
import sys, json, os

pending_file = sys.argv[1]
commit_hash  = sys.argv[2]
commit_msg   = sys.argv[3]
timestamp    = sys.argv[4]
repo         = sys.argv[5]
insertions   = int(sys.argv[6])
deletions    = int(sys.argv[7])
files_raw    = sys.argv[8]

files = [f for f in files_raw.splitlines() if f.strip()]

entry = {
    "hash":       commit_hash,
    "message":    commit_msg,
    "files":      files,
    "insertions": insertions,
    "deletions":  deletions,
    "timestamp":  timestamp,
    "repo":       repo,
}

# Read existing data or start fresh
data = {"commits": []}
if os.path.isfile(pending_file):
    try:
        with open(pending_file, "r") as fh:
            data = json.load(fh)
        if not isinstance(data, dict) or "commits" not in data:
            data = {"commits": []}
    except Exception:
        data = {"commits": []}

data["commits"].append(entry)

with open(pending_file, "w") as fh:
    json.dump(data, fh, indent=2)
PYEOF
  exit 0
fi

if command -v node &>/dev/null; then
  node - "$PENDING_FILE" "$COMMIT_HASH" "$COMMIT_MSG" "$COMMIT_TIMESTAMP" "$REPO_NAME" \
    "$INSERTIONS" "$DELETIONS" "$FILES_CHANGED" <<'JSEOF' 2>/dev/null
const fs   = require('fs');
const args = process.argv.slice(2);
const [pendingFile, hash, message, timestamp, repo, ins, del_, filesRaw] = args;

const files = filesRaw.split('\n').filter(f => f.trim() !== '');
const entry = {
  hash,
  message,
  files,
  insertions: parseInt(ins, 10),
  deletions:  parseInt(del_, 10),
  timestamp,
  repo,
};

let data = { commits: [] };
if (fs.existsSync(pendingFile)) {
  try {
    const parsed = JSON.parse(fs.readFileSync(pendingFile, 'utf8'));
    if (parsed && Array.isArray(parsed.commits)) {
      data = parsed;
    }
  } catch (_) {}
}

data.commits.push(entry);
fs.writeFileSync(pendingFile, JSON.stringify(data, null, 2));
JSEOF
  exit 0
fi

if command -v jq &>/dev/null; then
  # Build JSON entry via jq
  FILES_JSON=$(echo "$FILES_CHANGED" | jq -R . | jq -s . 2>/dev/null)
  NEW_ENTRY=$(jq -n \
    --arg hash      "$COMMIT_HASH" \
    --arg message   "$COMMIT_MSG" \
    --argjson files "$FILES_JSON" \
    --argjson ins   "$INSERTIONS" \
    --argjson del   "$DELETIONS" \
    --arg ts        "$COMMIT_TIMESTAMP" \
    --arg repo      "$REPO_NAME" \
    '{hash:$hash,message:$message,files:$files,insertions:$ins,deletions:$del,timestamp:$ts,repo:$repo}' \
    2>/dev/null)

  if [ -f "$PENDING_FILE" ]; then
    UPDATED=$(jq --argjson entry "$NEW_ENTRY" '.commits += [$entry]' "$PENDING_FILE" 2>/dev/null)
    if [ $? -eq 0 ]; then
      echo "$UPDATED" > "$PENDING_FILE" 2>/dev/null
      exit 0
    fi
  fi

  # File doesn't exist or jq failed — write fresh
  jq -n --argjson entry "$NEW_ENTRY" '{commits:[$entry]}' > "$PENDING_FILE" 2>/dev/null
  exit 0
fi

# Fallback: no JSON tool available — write a fresh single-entry file
FILES_JSON_ARRAY="[]"
if [ -n "$FILES_CHANGED" ]; then
  FILES_JSON_ARRAY=$(printf '%s\n' "$FILES_CHANGED" | awk 'BEGIN{printf "["} NR>1{printf ","} {gsub(/"/,"\\\""); printf "\"%s\"",$0} END{printf "]"}')
fi

cat > "$PENDING_FILE" 2>/dev/null <<JSONEOF
{
  "commits": [
    {
      "hash": "$COMMIT_HASH",
      "message": "$COMMIT_MSG",
      "files": $FILES_JSON_ARRAY,
      "insertions": $INSERTIONS,
      "deletions": $DELETIONS,
      "timestamp": "$COMMIT_TIMESTAMP",
      "repo": "$REPO_NAME"
    }
  ]
}
JSONEOF

exit 0
