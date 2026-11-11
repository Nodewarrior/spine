#!/bin/bash
# Self-check: edit-time rules (spine-rules.sh + spine-rules-index.sh).
# Runs in a throwaway HOME/vault/repo; touches nothing real. Usage: bash tests/test-edit-rules.sh
set -euo pipefail
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" SPINE_VAULT_PATH="$T/vault" TMPDIR="$T/tmp"
mkdir -p "$HOME/.spine" "$TMPDIR" "$SPINE_VAULT_PATH/acme/Checkout" "$SPINE_VAULT_PATH/acme/Search"
echo '{}' > "$HOME/.spine/config.json"
fail() { echo "FAIL: $1"; exit 1; }

# Hub with rules; its own list mixes an exact path, a glob and another repo.
cat > "$SPINE_VAULT_PATH/acme/Checkout/Checkout.md" <<'EOF'
# Checkout (acme)

## Rules (read before changing this feature)
- Never append query params to the GraphQL uri; the server forwards them.

**Files changed:**
- `src/api/useApollo.ts` — client
- `src/pay/**`
- `acme-be:Api/Pay.cs`
- `app/[slug]/page.tsx`
- `user/no-extension-branch`

## Fixes
EOF
# Leaf doc without rules → maps to its hub. Inline format with a hash that must be skipped.
cat > "$SPINE_VAULT_PATH/acme/Checkout/2026-11-01 Fix - Double Param.md" <<'EOF'
**Files changed:** `src/api/customFetch.ts` (commit `1399f675`)
EOF
# Feature without rules → never indexed.
printf '**Files changed:** `src/search/index.ts`\n' > "$SPINE_VAULT_PATH/acme/Search/Search.md"

R="$T/acme"; mkdir -p "$R/src/api" "$R/src/other"
git -C "$T" init -q acme && git -C "$R" remote add origin git@example.com:org/acme.git
touch "$R/src/api/useApollo.ts" "$R/src/api/customFetch.ts" "$R/src/other/x.ts"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm init

run() { printf '{"hook_event_name":"%s","session_id":"%s","agent_id":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "${4:-}" "$3" | bash "$HOOKS/spine-rules.sh"; }

# Index content
run PostToolUse s0 "$R/src/other/x.ts" >/dev/null
IDX="$HOME/.spine/rules-index.tsv"
grep -q $'^acme\tsrc/api/useApollo.ts\t' "$IDX" || fail "exact path not indexed"
grep -q $'^acme\tsrc/api/customFetch.ts\t.*Checkout/Checkout.md$' "$IDX" || fail "leaf doc not mapped to hub"
grep -q $'^acme-be\tApi/Pay.cs\t' "$IDX" || fail "repo prefix not parsed"
grep -q '1399f675' "$IDX" && fail "commit hash indexed as a path"
grep -q 'search/index.ts' "$IDX" && fail "doc without rules indexed"
grep -q 'no-extension-branch' "$IDX" && fail "branch name indexed as a path"

# 1. Read of a listed file → rules injected once per session
OUT=$(run PostToolUse s1 "$R/src/api/useApollo.ts")
echo "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("Never append query params")' >/dev/null || fail "rules not injected on Read"
[ -z "$(run PostToolUse s1 "$R/src/api/customFetch.ts")" ] || fail "same note injected twice in one session"

# 2. Edit after the rules were shown → allowed silently
[ -z "$(run PreToolUse s1 "$R/src/api/useApollo.ts")" ] || fail "edit blocked after rules were shown"

# 3. Edit without a prior Read → denied once with the rules, then allowed
OUT=$(run PreToolUse s2 "$R/src/pay/new/Card.tsx")   # glob match; Write into a dir that does not exist yet
echo "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("Never append"))' >/dev/null || fail "first edit not denied with rules"
[ -z "$(run PreToolUse s2 "$R/src/pay/new/Card.tsx")" ] || fail "retry was blocked again"

# 3b. A subagent has its own context: rules shown to the parent (s1) are shown to it again
OUT=$(run PreToolUse s1 "$R/src/api/useApollo.ts" agent-1)
echo "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null || fail "subagent edit not denied"

# 3c. Compaction drops the rules from context → they show again in the same session
echo '{"session_id":"s1","source":"compact"}' | bash "$HOOKS/spine-session-start.sh" >/dev/null
echo "$(run PostToolUse s1 "$R/src/api/useApollo.ts")" | grep -q 'Never append' || fail "rules not shown again after compact"
[ -z "$(run PreToolUse s1 "$R/src/api/useApollo.ts" agent-1)" ] && fail "subagent state survived compact" || true

# 3d. Bracket paths (Next.js routes) match literally
echo "$(run PostToolUse s8 "$R/app/[slug]/page.tsx")" | grep -q 'Never append' || fail "bracket path did not match"

# 4. Unrelated file, non-git file → silent
[ -z "$(run PreToolUse s3 "$R/src/other/x.ts")" ] || fail "unrelated file produced output"
[ -z "$(run PreToolUse s3 "$T/loose.md")" ] || fail "non-git file produced output"

# 5. Remote name with no vault folder → checkout folder name (renamed remote, vault folder acme)
mkdir -p "$T/clone" && git -C "$T/clone" init -q acme && mkdir -p "$T/clone/acme/src/api"
git -C "$T/clone/acme" remote add origin https://example.com/org/acme-renamed-app.git
echo "$(run PostToolUse s4a "$T/clone/acme/src/api/useApollo.ts")" | grep -q 'Never append' || fail "checkout-name fallback did not match"
(cd "$T/clone/acme/src" && echo '{"session_id":"s4s","source":"startup"}' | bash "$HOOKS/spine-session-start.sh") |
  grep -qE 'Spine Vault Index (—|\\u2014) acme\\n' || fail "session start: checkout-name fallback did not load the vault index"
# Remote name that is a vault symlink alias → the alias target (frontend -> web)
ln -s acme "$SPINE_VAULT_PATH/acme-web"
mkdir -p "$T/aliased" && git -C "$T/aliased" init -q && mkdir -p "$T/aliased/src/api"
git -C "$T/aliased" remote add origin git@example.com:org/acme-web.git
echo "$(run PostToolUse s4b "$T/aliased/src/api/useApollo.ts")" | grep -q 'Never append' || fail "vault alias did not match"

# Worktree with another folder name still resolves to the repo
git -C "$R" worktree add -q "$T/acme-wt" 2>/dev/null
OUT=$(run PostToolUse s4 "$T/acme-wt/src/api/useApollo.ts")
echo "$OUT" | grep -q 'Never append' || fail "worktree did not match"

# 6. Index refreshes when a note changes
sleep 1; printf '\n- Keep one cache layer per request.\n' >> "$SPINE_VAULT_PATH/acme/Checkout/Checkout.md"
printf '**Files changed:** `src/other/x.ts`\n' > "$SPINE_VAULT_PATH/acme/Checkout/Plan - X.md"
echo "$(run PostToolUse s5 "$R/src/other/x.ts")" | grep -q 'Spine rules from' || fail "index not rebuilt after note change"

# 7. Opt-out
echo '{"editRules": false}' > "$HOME/.spine/config.json"
[ -z "$(run PreToolUse s6 "$R/src/api/useApollo.ts")" ] || fail "editRules:false not honoured"
echo '{}' > "$HOME/.spine/config.json"

# 8. Budget: no-match path under 100 ms (median of 5 runs, timed with the bash built-in)
TIMEFORMAT=%R
MS=$(for _ in 1 2 3 4 5; do
  { time run PreToolUse s7 "$R/src/other/y.ts" >/dev/null; } 2>&1 | awk '{ printf "%d\n", $1 * 1000 }'
done | sort -n | sed -n 3p)
[ "$MS" -lt 100 ] || fail "no-match path took ${MS} ms (budget 100 ms)"

echo "PASS: edit-time rules (no-match median ${MS} ms)"
