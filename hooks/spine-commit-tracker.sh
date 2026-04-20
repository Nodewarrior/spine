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

# Use diff-tree --numstat for reliable stats. Handle initial commits via empty tree.
EMPTY_TREE="4b825dc642cb6eb9a060e54bf899d15363da7b23"
PARENT=$(git rev-parse --verify HEAD~1 2>/dev/null || echo "$EMPTY_TREE")
NUMSTAT=$(git diff-tree --numstat --no-commit-id -r "$PARENT" HEAD 2>/dev/null)

FILES_CHANGED=$(echo "$NUMSTAT" | awk '{print $3}' | grep -v '^$')
CHANGED_FILES_COUNT=$(echo "$FILES_CHANGED" | grep -c . 2>/dev/null || echo 0)
INSERTIONS=$(echo "$NUMSTAT" | awk '{s+=$1} END{print s+0}')
DELETIONS=$(echo "$NUMSTAT" | awk '{s+=$2} END{print s+0}')
TOTAL_CHANGES=$((INSERTIONS + DELETIONS))

# Skip trivial commits (less than 20 lines changed AND only 1 file)
if [ "$TOTAL_CHANGES" -lt 20 ] && [ "$CHANGED_FILES_COUNT" -le 1 ]; then
  exit 0
fi

# Skip merge commits
if echo "$COMMIT_MSG" | grep -qiE '^merge'; then
  exit 0
fi

# Skip style/lint/chore/docs commits (with or without colon)
if echo "$COMMIT_MSG" | grep -qiE '^(style|lint|chore|docs)(\(.*\))?[:/! ]'; then
  exit 0
fi

# Ensure .spine directory exists in vault
mkdir -p "$VAULT_PATH/.spine" 2>/dev/null

PENDING_FILE="$VAULT_PATH/.spine/pending-commits.json"
LOCK_FILE="$VAULT_PATH/.spine/pending-commits.lock"

# Acquire file lock to prevent concurrent write races.
# flock is available on macOS 13+ and all Linux. If unavailable, proceed without lock.
LOCK_FD=9
if command -v flock &>/dev/null; then
  exec 9>"$LOCK_FILE"
  flock -w 5 9 2>/dev/null || exit 0
fi

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

# Read existing data; preserve corrupt files instead of silently resetting
data = {"commits": []}
if os.path.isfile(pending_file):
    try:
        with open(pending_file, "r") as fh:
            data = json.load(fh)
        if not isinstance(data, dict) or "commits" not in data:
            raise ValueError("malformed pending-commits.json")
    except Exception:
        # Preserve corrupt file for recovery instead of losing tracked commits
        import shutil, datetime
        corrupt_name = pending_file + ".corrupt." + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        shutil.copy2(pending_file, corrupt_name)
        data = {"commits": []}

data["commits"].append(entry)

# Atomic write: write to temp file then rename to prevent partial writes
import tempfile
dir_name = os.path.dirname(pending_file)
fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
with os.fdopen(fd, "w") as fh:
    json.dump(data, fh, indent=2)
os.replace(tmp_path, pending_file)
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
    if (!parsed || !Array.isArray(parsed.commits)) {
      throw new Error('malformed');
    }
    data = parsed;
  } catch (_) {
    // Preserve corrupt file for recovery
    const ts = new Date().toISOString().replace(/[^0-9]/g, '').slice(0, 14);
    fs.copyFileSync(pendingFile, pendingFile + '.corrupt.' + ts);
  }
}

data.commits.push(entry);
// Atomic write: write to temp file then rename
const tmpFile = pendingFile + '.tmp.' + process.pid;
fs.writeFileSync(tmpFile, JSON.stringify(data, null, 2));
fs.renameSync(tmpFile, pendingFile);
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

# Fallback: no JSON tool available — write a fresh single-entry file.
# Escape special characters in commit message for valid JSON.
ESCAPED_MSG=$(printf '%s' "$COMMIT_MSG" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')

FILES_JSON_ARRAY="[]"
if [ -n "$FILES_CHANGED" ]; then
  FILES_JSON_ARRAY=$(printf '%s\n' "$FILES_CHANGED" | awk 'BEGIN{printf "["} NR>1{printf ","} {gsub(/"/,"\\\""); printf "\"%s\"",$0} END{printf "]"}')
fi

cat > "$PENDING_FILE" 2>/dev/null <<JSONEOF
{
  "commits": [
    {
      "hash": "$COMMIT_HASH",
      "message": "$ESCAPED_MSG",
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
