#!/bin/bash
# Self-check for scripts/spine-team-board.py: joins the live-session registry with episode
# records, flags overlaps only between concurrently active sessions, never reads *.key files.
# Runs in a throwaway HOME/vault. Usage: bash tests/test-team-board.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" SPINE_VAULT_PATH="$T/vault"
REG="$HOME/.claude/sessions"; mkdir -p "$REG" "$SPINE_VAULT_PATH/.spine/episodes" "$T/app"
git -C "$T/app" init -q -b feature/x
git -C "$T/app" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init  # a branch needs a commit
NOW=$(($(date +%s) * 1000)); OLD=$((NOW - 3 * 86400 * 1000))
LIVE=$$   # this shell is alive; 999999 is not
reg() { printf '{"pid":"%s","sessionId":"%s","cwd":"%s","name":"%s","status":"%s","updatedAt":"%s"}' "$1" "$2" "$3" "$4" "$5" "$6" > "$REG/$1$7.json"; }
reg $LIVE s-alpha "$T/app" alpha busy $NOW ""
reg $LIVE s-beta  "$T/app" beta  idle $NOW "b"
reg $LIVE s-gamma "$T/app" gamma idle $OLD "c"
reg 999999 s-dead "$T/app" dead busy $NOW ""
echo "SECRET-MUST-NOT-BE-READ" > "$REG/$LIVE.deadbeef.key"
cat > "$SPINE_VAULT_PATH/.spine/episodes/app.md" <<EP
## 2026-10-05 — alpha work
- **session:** \`s-alpha\` (resume: \`claude --resume s-alpha\`)
- **last prompt:** fix the checkout form
- **files touched:** \`forms/Checkout.tsx\`, \`lib/price.ts\`

## 2026-10-05 — beta work
- **session:** \`s-beta\` (resume: \`claude --resume s-beta\`)
- **files touched:** \`lib/price.ts\`
EP
OUT=$(python3 "$ROOT/scripts/spine-team-board.py")
fail() { echo "FAIL: $1"; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q '3 sessions · 1 busy' || fail "dead pid should be dropped (expect 3 sessions)"
echo "$OUT" | grep -q 'last ask: fix the checkout form' || fail "episode not joined"
echo "$OUT" | grep -q '⚠ same checkout as beta' || fail "concurrent same-checkout not flagged"
echo "$OUT" | grep -q '⚠ also editing lib/price.ts with beta' || fail "shared file not flagged"
echo "$OUT" | grep -A4 'gamma' | grep -q 'same checkout' && fail "idle-for-days session flagged as overlap"
echo "$OUT" | grep -A4 'gamma' | grep -q '⚠ idle 3d' || fail "stale session not flagged"
echo "$OUT" | grep -q 'SECRET' && fail ".key file was read"
python3 "$ROOT/scripts/spine-team-board.py" --json | python3 -c 'import json,sys; assert len(json.load(sys.stdin)) == 3'
echo "PASS"
