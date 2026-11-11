#!/bin/bash
# Spine — edit-time rules. Shows a note's "## Rules" when Claude touches a file the note lists.
#   PostToolUse(Read)       → inject the rules as additionalContext (arrives before the edit is planned)
#   PreToolUse(Edit|Write)  → if not shown yet this session, deny once with the rules as the reason;
#                             PreToolUse additionalContext would only arrive after the edit ran
# Each note is shown once per session. Silent (no output) when nothing matches.
# Opt out with "editRules": false in ~/.spine/config.json.
set -uo pipefail

# Runs before every Read/Edit, and each process start costs ~20 ms, so the no-match path uses
# only jq, find and git; everything else is a bash built-in.
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
# \x1f separator: tab is IFS whitespace, so an empty field would shift the ones after it.
# agent_id is set inside a subagent, which has its own context and must see the rules itself.
IFS=$'\x1f' read -r EVENT FILE SID AGENT < <(jq -r '[.hook_event_name, (.tool_input.file_path // .tool_input.notebook_path), .session_id, .agent_id] | map(. // "") | join("\u001f")' 2>/dev/null)
[[ "${FILE:-}" == /* ]] || exit 0

CFG="$HOME/.spine/config.json"
if [ -f "$CFG" ]; then
  read -r -d '' C < "$CFG" || true
  [[ "$C" =~ \"editRules\"[[:space:]]*:[[:space:]]*false ]] && exit 0
fi

# --- Index: build when missing, rebuild when any note is newer than it ---
IDX="$HOME/.spine/rules-index.tsv"
if [ ! -f "$IDX" ]; then
  VAULT=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)
  [ -d "$VAULT" ] || exit 0
  bash "$SCRIPT_DIR/spine-rules-index.sh" "$VAULT" "$IDX"
else
  IFS=$'\t' read -r _ VAULT < "$IDX"
  if [ -n "$(find "$VAULT" -name '*.md' -newer "$IDX" -not -path '*/.obsidian/*' -not -path '*/.spine/*' -print -quit 2>/dev/null)" ]; then
    bash "$SCRIPT_DIR/spine-rules-index.sh" "$VAULT" "$IDX"
  fi
fi

# --- Repo and repo-relative path ---
DIR="${FILE%/*}"
while [ -n "$DIR" ] && [ ! -d "$DIR" ]; do DIR="${DIR%/*}"; done   # Write may create dirs
[ -n "$DIR" ] || exit 0
# --show-prefix is resolved by git, so /tmp vs /private/tmp symlinks do not matter
GIT=$(git -C "$DIR" rev-parse --show-prefix --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
{ read -r PREFIX; read -r COMMON; } <<<"$GIT"
REL="$PREFIX${FILE#"$DIR"/}"
# Repo = the vault folder for this checkout. Candidates: the origin remote name (read from the
# shared git config, so worktrees such as myapp-hotfix agree), then the main checkout's
# folder name (remote acme-web-app lives in vault folder myapp). A vault symlink alias
# (frontend -> web) resolves to its target, the name the index uses.
REMOTE=""; SEC=""
while IFS= read -r L; do
  case "$L" in
    \[*) SEC="$L" ;;
    *url*=*) [ "$SEC" = '[remote "origin"]' ] && { REMOTE="${L#*=}"; break; } ;;
  esac
done < "$COMMON/config"
REMOTE="${REMOTE##*[/:]}"; REMOTE="${REMOTE%.git}"
C="${COMMON%/.git}"; CHECKOUT="${C##*/}"
REPO=""
for CAND in "$REMOTE" "$CHECKOUT"; do
  [ -n "$CAND" ] && [ -e "$VAULT/$CAND" ] || continue
  if [ -L "$VAULT/$CAND" ]; then L=$(readlink "$VAULT/$CAND"); L="${L%/}"; CAND="${L##*/}"; fi
  REPO="$CAND"; break
done
[ -n "$REPO" ] || exit 0

# --- Match, skipping notes already shown in this context (session, or subagent) ---
# The SessionStart hook deletes this file on compact/clear, when shown rules leave the context.
STATE="${TMPDIR:-/tmp}/spine-rules/${SID:-nosession}${AGENT:+.$AGENT}"
SHOWN=$'\n'
[ -f "$STATE" ] && { IFS= read -r -d '' S < "$STATE" || true; SHOWN+="$S"; }
NOTES=()
{
  read -r _   # header
  while IFS=$'\t' read -r R GLOB NOTE; do
    [ "$R" = "$REPO" ] || continue
    # shellcheck disable=SC2053  # GLOB is a pattern on purpose; "*" also spans "/"
    [[ "$REL" == "$GLOB" || "$REL" == $GLOB ]] || continue   # exact first: [slug] is a path, not a class
    case "$SHOWN" in *$'\n'"$NOTE"$'\n'*) continue ;; esac
    SHOWN+="$NOTE"$'\n'
    NOTES+=("$NOTE")
  done
} < "$IDX"
[ ${#NOTES[@]} -gt 0 ] || exit 0

TEXT=""
for NOTE in "${NOTES[@]}"; do
  TEXT+="Spine rules from [[$(basename "$NOTE" .md)]] (they apply to \`$REL\`):"$'\n'
  TEXT+=$(awk '/^## Rules/ { on = 1; next } on && /^## / { exit } on' "$NOTE")$'\n\n'
done
TEXT="${TEXT:0:9000}"   # hook context is capped at 10,000 characters

mkdir -p "$(dirname "$STATE")"
printf '%s\n' "${NOTES[@]}" >> "$STATE"

if [ "$EVENT" = "PreToolUse" ]; then
  jq -n --arg r "Spine: the rules below apply to this file and were not shown yet in this session. Check your change against them, then retry the same edit (it will not be blocked again).

$TEXT" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
else
  jq -n --arg c "$TEXT" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
fi
