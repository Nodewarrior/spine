#!/bin/bash
# Build the edit-time rules index: one line per (repo, path or glob, note that holds the "## Rules").
# Usage: spine-rules-index.sh <vault> <out-file>
# - Paths come from each doc's "**Files changed:**" block (inline backticks, or a bullet list).
# - A path's repo is the doc's top vault folder, unless written as `other-repo:path`.
# - A doc with its own "## Rules" maps to itself; a doc without one maps to its feature hub
#   ({Feature}/{Feature}.md) when the hub has rules. Docs that reach no rules are left out.
# Line 1 is a header holding the vault path, so the hook can check freshness without resolving it.
set -uo pipefail

VAULT="${1%/}"; OUT="$2"
[ -d "$VAULT" ] || exit 0
mkdir -p "$(dirname "$OUT")"
TMP="$OUT.tmp.$$"

{
  printf '#vault\t%s\n' "$VAULT"
  # One awk run reads every doc (file list on stdin), so hub lookups see the whole vault.
  find "$VAULT" -name '*.md' -not -path '*/.obsidian/*' -not -path '*/.spine/*' |
    awk -v vault="$VAULT/" '
      # A path token: no spaces, and the last segment has a file extension or a glob "*"
      # (skips hashes, words, code, and branch names such as user/fix-login).
      function addtok(f, t) {
        sub(/^\.\//, "", t)
        if (t !~ /^[A-Za-z0-9_.@*\/:+()\[\]-]+$/) return
        if (t !~ /\.[A-Za-z0-9]+$/ && t !~ /\*[^\/]*$/) return
        paths[++n] = f "\t" t
      }
      function toks(f, s, first) {
        while (match(s, /`[^`]+`/)) {
          addtok(f, substr(s, RSTART + 1, RLENGTH - 2))
          if (first) return
          s = substr(s, RSTART + RLENGTH)
        }
      }
      {
        f = $0; inlist = 0
        while ((getline line < f) > 0) {
          if (line ~ /^## Rules/) rules[f] = 1
          if (line ~ /\*\*Files changed:\*\*/) {
            inlist = 1; s = line; sub(/.*\*\*Files changed:\*\*/, "", s); toks(f, s, 0)
          } else if (inlist && line ~ /^[[:space:]]*[-*] /) toks(f, line, 1)
          else inlist = 0
        }
        close(f)
      }
      END {
        for (i = 1; i <= n; i++) {
          split(paths[i], p, "\t"); f = p[1]; t = p[2]
          target = ""
          if (f in rules) target = f
          else {
            d = f; sub(/\/[^\/]*$/, "", d)
            hub = d; sub(/.*\//, "", hub); hub = d "/" hub ".md"
            if (hub in rules) target = hub
          }
          if (target == "") continue
          rel = substr(f, length(vault) + 1); repo = rel; sub(/\/.*/, "", repo)
          if (match(t, /^[A-Za-z0-9_.-]+:/)) { repo = substr(t, 1, RLENGTH - 1); t = substr(t, RLENGTH + 1) }
          key = repo "\t" t "\t" target
          if (!(key in seen)) { seen[key] = 1; print key }
        }
      }'
} > "$TMP" && mv "$TMP" "$OUT"
