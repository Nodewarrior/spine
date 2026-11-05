#!/bin/bash
# Self-check: episode upsert across turns + post-compaction checkpoint injection.
# Runs in a throwaway HOME/vault; touches nothing real. Usage: bash tests/test-compaction-checkpoint.sh
set -euo pipefail
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" SPINE_VAULT_PATH="$T/vault"
mkdir -p "$HOME/.spine" "$SPINE_VAULT_PATH/demo" "$T/demo"
echo '{"episodes": true}' > "$HOME/.spine/config.json"
cd "$T/demo"   # not a git repo -> repo name "demo"
TR="$T/t.jsonl"; EP="$SPINE_VAULT_PATH/.spine/episodes/demo.md"
say() { printf '{"type":"user","timestamp":"2026-09-23T10:0%s:00Z","message":{"content":"%s"}}\n' "$1" "$2" >> "$TR"; }
P='{"session_id":"s1","transcript_path":"'"$TR"'"}'
fail() { echo "FAIL: $1"; exit 1; }

say 1 'fix the login redirect'
bash "$HOOKS/spine-episode-extract.sh" "$P"
say 2 'now add a test for it'
bash "$HOOKS/spine-episode-extract.sh" "$P"                 # 2nd turn (Stop)
echo "$P" | bash "$HOOKS/spine-episode-extract.sh"         # PreCompact (stdin)

[ "$(grep -c '^## ' "$EP")" = 1 ] || fail "expected 1 upserted block"
grep -q 'now add a test for it' "$EP" || fail "later ask missing"
grep -q '^## 2026-09-23 — fix the login redirect' "$EP" || fail "title fallback"

OUT=$(echo '{"session_id":"s1","source":"compact"}' | bash "$HOOKS/spine-session-start.sh")
echo "$OUT" | grep -q 'Pre-compaction checkpoint' || fail "checkpoint not injected on compact"
echo "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' || fail "invalid JSON"
OUT=$(echo '{"session_id":"s1","source":"startup"}' | bash "$HOOKS/spine-session-start.sh")
echo "$OUT" | grep -q 'Pre-compaction checkpoint' && fail "checkpoint leaked into startup"

# --- 1. Concurrent sessions of one repo must not lose each other's episodes ---
CONC="$T/conc"; mkdir -p "$CONC" && cd "$CONC"
N=12
for i in $(seq 1 $N); do
  TRC="$T/conc-$i.jsonl"
  printf '{"type":"user","timestamp":"2026-09-23T10:00:00Z","message":{"content":"task number %s"}}\n' "$i" > "$TRC"
  bash "$HOOKS/spine-episode-extract.sh" '{"session_id":"conc-'"$i"'","transcript_path":"'"$TRC"'"}' &
done
wait
CONC_EP="$SPINE_VAULT_PATH/.spine/episodes/conc.md"
[ "$(grep -c '^## ' "$CONC_EP")" = "$N" ] || fail "concurrent upserts lost episodes: $(grep -c '^## ' "$CONC_EP") of $N kept"
ls -A "$SPINE_VAULT_PATH/.spine/episodes/" | grep -E '\.tmp$' >/dev/null && fail "temp file left behind"  # *.lock files stay by design
cd "$T/demo"

# --- 2. The checkpoint works with only `episodes` on (autoLoad and tier3 off) ---
echo '{"episodes": true, "autoLoad": false, "tier3": false}' > "$HOME/.spine/config.json"
OUT=$(echo '{"session_id":"s1","source":"compact"}' | bash "$HOOKS/spine-session-start.sh")
echo "$OUT" | grep -q 'Pre-compaction checkpoint' || fail "checkpoint skipped when autoLoad and tier3 are off"
echo "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' || fail "invalid JSON with episodes-only config"
OUT=$(echo '{"session_id":"s1","source":"startup"}' | bash "$HOOKS/spine-session-start.sh")
[ -z "$OUT" ] || fail "startup with everything off should inject nothing"
echo "PASS"
