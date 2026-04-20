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

# Gather commit metadata in a single git call
IFS=$'\x01' read -r COMMIT_HASH COMMIT_MSG COMMIT_TIMESTAMP \
  < <(git log -1 --pretty="%h%x01%s%x01%aI" 2>/dev/null)

# Use diff-tree --numstat for reliable stats. Handle initial commits via empty tree.
EMPTY_TREE="4b825dc642cb6eb9a060e54bf899d15363da7b23"
PARENT=$(git rev-parse --verify HEAD~1 2>/dev/null || echo "$EMPTY_TREE")
NUMSTAT=$(git diff-tree --numstat --no-commit-id -r "$PARENT" HEAD 2>/dev/null)

# Extract all stats in a single awk pass
eval "$(echo "$NUMSTAT" | awk '
  $3 != "" { files = files (files ? "\n" : "") $3; ins += $1; del += $2; cnt++ }
  END { printf "INSERTIONS=%d\nDELETIONS=%d\nCHANGED_FILES_COUNT=%d\n", ins, del, cnt }
')"
FILES_CHANGED=$(echo "$NUMSTAT" | awk '$3 != "" {print $3}')
TOTAL_CHANGES=$((INSERTIONS + DELETIONS))

# Skip trivial commits (less than 20 lines changed AND only 1 file)
if [ "$TOTAL_CHANGES" -lt 20 ] && [ "$CHANGED_FILES_COUNT" -le 1 ]; then
  exit 0
fi

# Skip merge and trivial-category commits using bash built-in regex (no subprocesses)
MSG_LOWER="${COMMIT_MSG,,}"
if [[ "$MSG_LOWER" =~ ^merge ]]; then
  exit 0
fi
if [[ "$MSG_LOWER" =~ ^(style|lint|chore|docs)(\(.*\))?[:/!\ ] ]]; then
  exit 0
fi

# Ensure .spine directory exists in vault
mkdir -p "$VAULT_PATH/.spine" 2>/dev/null

PENDING_FILE="$VAULT_PATH/.spine/pending-commits.json"
LOCK_FILE="$VAULT_PATH/.spine/pending-commits.lock"

# Acquire file lock to prevent concurrent write races.
# flock is native on Linux; on macOS requires brew install util-linux. Falls back gracefully.
LOCK_FD=9
if command -v flock &>/dev/null; then
  exec 9>"$LOCK_FILE"
  flock -w 5 9 2>/dev/null || exit 0
fi

# Append commit entry to pending-commits.json using a fallback ladder.
# Why: Spine has zero dependencies, so we can't assume any runtime is available.
# python3 and node handle JSON natively; jq is a lightweight fallback; raw bash is last resort.
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
      # Atomic write via temp file
      TMP_JQ="$PENDING_FILE.tmp.$$"
      echo "$UPDATED" > "$TMP_JQ" 2>/dev/null && mv "$TMP_JQ" "$PENDING_FILE" 2>/dev/null
      exit 0
    else
      # Preserve corrupt file for recovery
      cp "$PENDING_FILE" "$PENDING_FILE.corrupt.$(date +%Y%m%d%H%M%S)" 2>/dev/null
    fi
  fi

  # File doesn't exist or was corrupt — write fresh via atomic rename
  TMP_JQ="$PENDING_FILE.tmp.$$"
  jq -n --argjson entry "$NEW_ENTRY" '{commits:[$entry]}' > "$TMP_JQ" 2>/dev/null && mv "$TMP_JQ" "$PENDING_FILE" 2>/dev/null
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
