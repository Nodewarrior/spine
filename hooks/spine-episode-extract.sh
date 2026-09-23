#!/bin/bash
# Spine Architecture — Episode extractor
# Called by the Stop hook with the hook payload JSON as $1, or by the
# PreCompact hook with the payload on stdin. Extracts a compact episode record
# from the session transcript into {vault}/.spine/episodes/{repo}.md — the
# episodic memory layer. Stop fires after every turn, so the session's record
# is upserted (replaced and moved to the bottom), never duplicated.
#
# Design constraints:
#   - Must NEVER break a session: any failure exits 0 silently.
#   - No LLM calls — pure deterministic extraction (fast, free, cache-neutral).
#   - Runs only when episodes are enabled: config `episodes` key, defaulting
#     to the value of `tier3` (episodic capture is an autonomous write).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PAYLOAD="${1:-}"
if [ -z "$PAYLOAD" ] && [ ! -t 0 ]; then
  PAYLOAD=$(cat 2>/dev/null || true)
fi
[ -z "$PAYLOAD" ] && exit 0

# --- Resolve vault path ---
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# --- Feature gate: episodes (default: follow tier3) ---
if ! command -v python3 &>/dev/null; then
  exit 0
fi
EPISODES_ENABLED=$(python3 -c "
import json, os
try:
    c = json.load(open(os.path.expanduser('~/.spine/config.json')))
except Exception:
    c = {}
print(str(c.get('episodes', c.get('tier3', False))).lower())
" 2>/dev/null || echo "false")
if [ "$EPISODES_ENABLED" != "true" ]; then
  exit 0
fi

# --- Detect repo (mirror session-start logic) ---
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi

EPISODES_DIR="$VAULT_PATH/.spine/episodes"
mkdir -p "$EPISODES_DIR" 2>/dev/null || exit 0

# --- Extract episode from transcript and append ---
# Payload passed as argv (heredoc occupies stdin for the script body).
python3 - "$EPISODES_DIR/$REPO_NAME.md" "$PAYLOAD" <<'PYEOF' 2>/dev/null
import json, sys, os, re, datetime, collections

MAX_PROMPTS = 12          # most recent human prompts kept per episode
MAX_PROMPT_CHARS = 200    # truncation per prompt
MAX_FILES = 15            # most recently touched files kept

def main():
    out_path = sys.argv[1]
    try:
        payload = json.loads(sys.argv[2])
    except Exception:
        return
    transcript = payload.get("transcript_path", "")
    session_id = payload.get("session_id", "unknown")
    if not transcript or not os.path.isfile(transcript):
        return
    # Pathological-transcript guard: the hook must never stall a session end.
    if os.stat(transcript).st_size > 200 * 1024 * 1024:
        return

    title = ""
    last_prompt = ""
    git_branch = ""
    first_ts = ""
    last_ts = ""
    first_prompt = ""
    prompts = collections.deque(maxlen=MAX_PROMPTS)
    files = {}                # insertion-ordered; re-touch moves to the end

    with open(transcript, "r", errors="replace") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            rtype = rec.get("type", "")
            ts = rec.get("timestamp", "")
            if ts:
                if not first_ts:
                    first_ts = ts
                last_ts = ts
            if rtype == "ai-title":
                clean = rec.get("aiTitle", "").replace("\n", " ").replace("\r", " ").strip()
                title = clean or title
            elif rtype == "last-prompt":
                last_prompt = rec.get("lastPrompt", "") or last_prompt
            elif rtype == "user" and not rec.get("isMeta") and not rec.get("isCompactSummary"):
                content = (rec.get("message") or {}).get("content", "")
                if isinstance(content, str) and content.strip():
                    text = content.strip()
                    if text.startswith("<") or text.startswith("Caveat:"):
                        continue  # hook/system-injected wrappers, not human prose
                    one_line = text[:MAX_PROMPT_CHARS].replace("\n", " ")
                    first_prompt = first_prompt or one_line
                    prompts.append(one_line)
                if rec.get("gitBranch"):
                    git_branch = rec["gitBranch"]
            elif rtype == "assistant":
                content = (rec.get("message") or {}).get("content", [])
                if isinstance(content, list):
                    for block in content:
                        if block.get("type") == "tool_use" and block.get("name") in ("Edit", "Write", "NotebookEdit"):
                            fp = (block.get("input") or {}).get("file_path", "")
                            if fp:
                                files.pop(fp, None)
                                files[fp] = True

    if not prompts and not title:
        return  # nothing worth recording

    # Transcripts rarely carry an ai-title record; the opening ask is the
    # best deterministic stand-in for what the session was about.
    title = title or first_prompt[:70].strip() or "untitled session"
    date = (last_ts or first_ts or datetime.date.today().isoformat())[:10]
    marker = f"- **session:** `{session_id}`"
    lines = [f"## {date} — {title}", ""]
    lines.append(f"{marker} (resume: `claude --resume {session_id}`)")
    if git_branch:
        lines.append(f"- **branch:** `{git_branch}`")
    if first_ts and last_ts:
        lines.append(f"- **span:** {first_ts[:16]} → {last_ts[:16]}")
    if last_prompt:
        lines.append(f"- **last prompt:** {last_prompt[:MAX_PROMPT_CHARS].replace(chr(10), ' ')}")
    if files:
        recent = list(files)[-MAX_FILES:]
        short = [os.path.join(os.path.basename(os.path.dirname(p)), os.path.basename(p)) for p in recent]
        lines.append(f"- **files touched:** {', '.join('`' + p + '`' for p in short)}")
    if prompts:
        lines.append("- **asks:**")
        for p in prompts:
            lines.append(f"  - {p}")
    lines.append("")

    # Upsert: drop this session's previous record, append the fresh one.
    # ponytail: no file lock — two sessions of the same repo stopping in the
    # same instant can lose one update; the next Stop rewrites it anyway.
    if os.path.isfile(out_path):
        with open(out_path, "r", errors="replace") as f:
            existing = f.read()
    else:
        existing = "# Episodes — session memory\n\n<!-- Upserted by spine-episode-extract.sh after each turn and before compaction. Newest at bottom. -->\n"
    blocks = re.split(r"(?m)^(?=## )", existing)
    kept = "".join(b for b in blocks if marker not in b).rstrip("\n")
    tmp = out_path + ".tmp"
    with open(tmp, "w") as f:
        f.write(kept + "\n\n" + "\n".join(lines) + "\n")
    os.replace(tmp, out_path)

main()
PYEOF

exit 0
