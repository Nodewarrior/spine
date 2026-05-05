#!/bin/bash
# Spine Architecture — post-commit hook
# Tier 3 (tier3: true):  Silently tracks commits to pending-commits.json for batch capture.
# Tier 1/2 (tier3: false): Prints a nudge suggesting /spine-capture. Default behavior.

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

# Check tier3 flag from ~/.spine/config.json (default: false)
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
# Normalize to lowercase
TIER3_ENABLED="${TIER3_ENABLED,,}"

# Gather commit metadata in a single git call
IFS=$'\x01' read -r COMMIT_HASH COMMIT_MSG COMMIT_TIMESTAMP \
  < <(git log -1 --pretty="%H%x01%s%x01%aI" 2>/dev/null)

# Use diff-tree --numstat for reliable stats. Handle initial commits via empty tree.
EMPTY_TREE="4b825dc642cb6eb9a060e54bf899d15363da7b23"
PARENT=$(git rev-parse --verify HEAD~1 2>/dev/null || echo "$EMPTY_TREE")
# Use -z for NUL-delimited output to handle all special chars in paths (tabs, spaces, etc.)
NUMSTAT_RAW=$(git diff-tree --numstat -z --no-commit-id -r "$PARENT" HEAD 2>/dev/null)

# Parse NUL-delimited numstat: format is "ins\tdel\tNULpath\0" per entry
INSERTIONS=0; DELETIONS=0; CHANGED_FILES_COUNT=0; FILES_CHANGED=""
while IFS=$'\t' read -r -d '' ins del path; do
  if [ -n "$path" ]; then
    INSERTIONS=$((INSERTIONS + ins))
    DELETIONS=$((DELETIONS + del))
    CHANGED_FILES_COUNT=$((CHANGED_FILES_COUNT + 1))
    FILES_CHANGED="${FILES_CHANGED:+$FILES_CHANGED
}$path"
  fi
done < <(printf '%s' "$NUMSTAT_RAW")
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

# Tier 3 off: nudge the user and exit (Tier 1/2 behavior)
if [[ "$TIER3_ENABLED" != "true" ]]; then
  echo "SPINE: Commit \"$COMMIT_MSG\" changed $CHANGED_FILES_COUNT files (+$INSERTIONS/-$DELETIONS). Consider running /spine-capture to document this work."
  exit 0
fi

# --- Tier 3: silent tracking below this line ---

# Ensure .spine directory exists in vault
mkdir -p "$VAULT_PATH/.spine" 2>/dev/null

PENDING_FILE="$VAULT_PATH/.spine/pending-commits.json"
LOCK_DIR="$VAULT_PATH/.spine/pending-commits.lockdir"

# Portable lock using mkdir (atomic on all POSIX systems including macOS).
LOCK_ACQUIRED=false
MY_PID=$$
for _attempt in 1 2 3 4 5; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$MY_PID" > "$LOCK_DIR/pid" 2>/dev/null
    LOCK_ACQUIRED=true
    trap '[ -f "$LOCK_DIR/pid" ] && [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "'"$MY_PID"'" ] && rm -rf "$LOCK_DIR" 2>/dev/null' EXIT
    break
  fi
  # Stale lock detection: only remove if the owning process is dead
  if [ -d "$LOCK_DIR" ]; then
    OWNER_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$OWNER_PID" ] && ! kill -0 "$OWNER_PID" 2>/dev/null; then
      rm -rf "$LOCK_DIR" 2>/dev/null
    elif [ -z "$OWNER_PID" ]; then
      # No PID file — use mtime fallback (cross-platform stat)
      if [[ "$OSTYPE" == darwin* ]]; then
        LOCK_MTIME=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
      else
        LOCK_MTIME=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
      fi
      LOCK_AGE=$(( $(date +%s) - LOCK_MTIME ))
      if [ "$LOCK_AGE" -gt 30 ]; then
        rm -rf "$LOCK_DIR" 2>/dev/null
      fi
    fi
  fi
  sleep 1
done
if [ "$LOCK_ACQUIRED" = false ]; then
  exit 0
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
        if not isinstance(data, dict) or not isinstance(data.get("commits"), list):
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
    # Validate commits is an array before appending
    COMMITS_TYPE=$(jq -r '.commits | type' "$PENDING_FILE" 2>/dev/null)
    if [ "$COMMITS_TYPE" = "array" ]; then
      UPDATED=$(jq --argjson entry "$NEW_ENTRY" '.commits += [$entry]' "$PENDING_FILE" 2>/dev/null)
      if [ $? -eq 0 ]; then
        TMP_JQ="$PENDING_FILE.tmp.$$"
        echo "$UPDATED" > "$TMP_JQ" 2>/dev/null && mv "$TMP_JQ" "$PENDING_FILE" 2>/dev/null
        exit 0
      fi
    fi
    # Malformed or parse failure — preserve corrupt file for recovery
    cp "$PENDING_FILE" "$PENDING_FILE.corrupt.$(date +%Y%m%d%H%M%S)" 2>/dev/null
  fi

  # File doesn't exist or was corrupt — write fresh via atomic rename
  TMP_JQ="$PENDING_FILE.tmp.$$"
  jq -n --argjson entry "$NEW_ENTRY" '{commits:[$entry]}' > "$TMP_JQ" 2>/dev/null && mv "$TMP_JQ" "$PENDING_FILE" 2>/dev/null
  exit 0
fi

# Fallback: no JSON tool available — log to a sidecar file instead of overwriting.
# Without a JSON parser we cannot safely append to the existing JSON array.
ESCAPED_MSG=$(printf '%s' "$COMMIT_MSG" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')

FILES_JSON_ARRAY="[]"
if [ -n "$FILES_CHANGED" ]; then
  FILES_JSON_ARRAY=$(printf '%s\n' "$FILES_CHANGED" | awk 'BEGIN{printf "["} NR>1{printf ","} {gsub(/"/,"\\\""); printf "\"%s\"",$0} END{printf "]"}')
fi

# If pending-commits.json already exists, write to a sidecar to avoid overwriting
FALLBACK_TARGET="$PENDING_FILE"
if [ -f "$PENDING_FILE" ]; then
  FALLBACK_TARGET="$VAULT_PATH/.spine/pending-commits.fallback.$(date +%s).json"
fi

cat > "$FALLBACK_TARGET" 2>/dev/null <<JSONEOF
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
