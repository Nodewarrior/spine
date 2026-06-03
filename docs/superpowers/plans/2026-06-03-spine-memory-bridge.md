# Spine Memory Bridge — "Coexist" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Spine's vault automatically available at session start so Claude has structured project knowledge without manual invocations — the "read half" that's been missing.

**Architecture:** Four components. (1) Extend the SessionStart hook to discover hub spine notes and inject a compact index + retrieval policy into the session context — pure shell, no LLM call. (2) New `/spine-recall` skill for on-demand deep pull of specific vault docs. (3) Ship a static retrieval policy file in the plugin. (4) Fix the Bash 3.2 compatibility bug in the existing hook. The "coexist" approach means we do NOT rewrite `MEMORY.md` signposts — the hook injection IS the bridge.

**Tech Stack:** Bash (3.2-compatible), Markdown (SKILL.md), JSON (hooks.json, config.json)

**Design Decisions (from brainstorm):**

| Decision | Choice |
|----------|--------|
| Primary pain | Auto-load on sit-down |
| How aggressive | SessionStart + on-demand |
| What to inject | Index + policy |
| Recall formality | Pragmatic policy-driven |
| Bridge approach | Coexist (hook IS the bridge) |
| Gating | Own flag (`autoLoad`), default on |

**Critical: Gating architecture.** The existing `spine-session-start.sh` gates ALL output behind `tier3: true` (which is `false` by default). The memory bridge uses a NEW flag `autoLoad` (default `true`) — independent of tier3. Both can fire in one session: autoLoad injects the vault index, tier3 injects the `/spine-scan` directive. The script concatenates both into a single `additionalContext` output.

**Critical: JSON encoding.** The injected content contains markdown with quotes, backslashes, and newlines. Raw `printf '%s'` produces invalid JSON. All injected content MUST be JSON-encoded via `python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'` or equivalent.

**Critical: Retrieval policy location.** The policy ships in the plugin at `${CLAUDE_PLUGIN_ROOT}/templates/retrieval-policy.md` (always available). Optional per-vault override at `{vault}/.spine/retrieval-policy.md` takes precedence if present.

**Testing approach:** This repo has no automated test framework for skills (they're markdown instructions). Verification is manual + a shell smoke test for the hook (run against a fixture vault, assert valid JSON output).

---

### Task 1: Create feature branch

**Files:**
- None (git operation only)

- [ ] **Step 1: Create and checkout branch**

```bash
git checkout -b feat/memory-bridge main
```

- [ ] **Step 2: Verify clean state**

```bash
git status
```

Expected: clean working tree on `feat/memory-bridge`.

---

### Task 2: Ship retrieval policy template

The SessionStart hook will read this file and inject it into session context. Ship it in the plugin so it's always available — no dependency on per-vault state.

**Files:**
- Create: `templates/retrieval-policy.md`

- [ ] **Step 1: Create the retrieval policy file**

Write `templates/retrieval-policy.md`:

```markdown
# Spine Retrieval Policy

When you need context on a feature, component, or past decision in this repo, follow these steps:

## Auto-Loaded Context

At session start, Spine injected a **vault index** listing all spine notes (feature hubs) for this repo. Use it as your map.

## Three-Hop Navigation

1. **Scan the index** — find the spine note matching the feature area you need
2. **Read the spine note** — it's the hub with wikilinks to all child docs (fixes, features, architecture, plans, decisions)
3. **Read the specific doc** — follow the wikilink to the doc with the detail you need

## When to Pull Vault Docs

- Before making changes to a feature area — check if architecture docs or decisions exist
- When debugging — check if a fix doc covers this area (root cause, code snippets)
- When planning — check if a plan doc already exists for this feature
- When you see a `[[wikilink]]` in any spine doc — you can read it from the vault

## On-Demand Deep Pull

Use `/spine-recall <feature>` to load all docs for a specific feature area into context at once.

## Do NOT

- Create duplicate docs — check the index first
- Ignore spine docs when they exist — they contain institutional knowledge
- Modify vault docs directly — use `/spine-update` or `/spine-capture`
```

- [ ] **Step 2: Commit**

```bash
git add templates/retrieval-policy.md
git commit -m "feat: add retrieval policy template for session-start injection"
```

---

### Task 3: Rewrite SessionStart hook with dual-gate architecture

This is the core component. The hook discovers hub spine notes, builds a compact index, reads the retrieval policy, and injects both into session context. It has two independent gates: `autoLoad` (default on) for the vault index, and `tier3` (default off) for the `/spine-scan` directive.

**Files:**
- Modify: `hooks/spine-session-start.sh`

- [ ] **Step 1: Read the current hook to confirm starting state**

Read `hooks/spine-session-start.sh`. Confirm it matches the version with the `tier3` gate and `${TIER3_ENABLED,,}` bash 4+ syntax on line 35.

- [ ] **Step 2: Rewrite the hook**

Replace the entire contents of `hooks/spine-session-start.sh` with:

```bash
#!/bin/bash
# Spine Architecture — SessionStart hook
# Two independent gates:
#   autoLoad (default: true)  → injects vault index + retrieval policy
#   tier3    (default: false) → injects /spine-scan directive
# Both can fire in one session. Output is a single JSON object.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Resolve vault path ---
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# --- Detect repo ---
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi
if [ ! -d "$VAULT_PATH/$REPO_NAME" ]; then
  exit 0
fi

# --- Read config flags ---
AUTOLOAD_ENABLED=true
TIER3_ENABLED=false
if [ -f "$HOME/.spine/config.json" ]; then
  if command -v python3 &>/dev/null; then
    AUTOLOAD_ENABLED=$(python3 -c "
import json
c = json.load(open('$HOME/.spine/config.json'))
print(str(c.get('autoLoad', True)).lower())
" 2>/dev/null || echo "true")
    TIER3_ENABLED=$(python3 -c "
import json
c = json.load(open('$HOME/.spine/config.json'))
print(str(c.get('tier3', False)).lower())
" 2>/dev/null || echo "false")
  elif command -v node &>/dev/null; then
    AUTOLOAD_ENABLED=$(node -e "
const c = require('$HOME/.spine/config.json');
console.log(String(c.autoLoad !== undefined ? c.autoLoad : true).toLowerCase());
" 2>/dev/null || echo "true")
    TIER3_ENABLED=$(node -e "
const c = require('$HOME/.spine/config.json');
console.log(String(c.tier3 || false).toLowerCase());
" 2>/dev/null || echo "false")
  elif command -v jq &>/dev/null; then
    AUTOLOAD_ENABLED=$(jq -r 'if .autoLoad == false then "false" else "true" end' "$HOME/.spine/config.json" 2>/dev/null || echo "true")
    TIER3_ENABLED=$(jq -r '.tier3 // false | tostring | ascii_downcase' "$HOME/.spine/config.json" 2>/dev/null || echo "false")
  fi
fi
# Normalize (Bash 3.2 compatible — no ${var,,})
AUTOLOAD_ENABLED=$(printf '%s' "$AUTOLOAD_ENABLED" | tr '[:upper:]' '[:lower:]')
TIER3_ENABLED=$(printf '%s' "$TIER3_ENABLED" | tr '[:upper:]' '[:lower:]')

# --- Build context parts ---
CONTEXT_PARTS=""

# Part 1: Auto-load vault index + retrieval policy
if [ "$AUTOLOAD_ENABLED" = "true" ]; then
  REPO_DIR="$VAULT_PATH/$REPO_NAME"
  INDEX="## Spine Vault Index — $REPO_NAME\n\n"
  INDEX="${INDEX}Features documented in this repo's vault:\n\n"

  FOUND_NOTES=0
  while IFS= read -r -d '' note_file; do
    TITLE=$(sed -n '/^---$/,/^---$/{ /^title:/{ s/^title:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//; p; q; } }' "$note_file" 2>/dev/null)
    if [ -z "$TITLE" ]; then
      TITLE=$(basename "$note_file" .md)
    fi
    FEATURE_DIR=$(basename "$(dirname "$note_file")")
    CHILD_COUNT=$(find "$(dirname "$note_file")" -maxdepth 1 -name "*.md" ! -name "$(basename "$note_file")" 2>/dev/null | wc -l | tr -d ' ')
    INDEX="${INDEX}- **${TITLE}** (${FEATURE_DIR}/) — ${CHILD_COUNT} docs\n"
    FOUND_NOTES=$((FOUND_NOTES + 1))
  done < <(grep -rlZ "type/spine" "$REPO_DIR" 2>/dev/null)

  if [ "$FOUND_NOTES" -eq 0 ]; then
    INDEX="${INDEX}_(No spine notes found for this repo. Use /spine-capture to create the first one.)_\n"
  fi

  # Read retrieval policy — per-vault override takes precedence
  POLICY=""
  if [ -f "$VAULT_PATH/.spine/retrieval-policy.md" ]; then
    POLICY=$(cat "$VAULT_PATH/.spine/retrieval-policy.md" 2>/dev/null)
  elif [ -f "$SCRIPT_DIR/../templates/retrieval-policy.md" ]; then
    POLICY=$(cat "$SCRIPT_DIR/../templates/retrieval-policy.md" 2>/dev/null)
  fi

  CONTEXT_PARTS="${INDEX}"
  if [ -n "$POLICY" ]; then
    CONTEXT_PARTS="${CONTEXT_PARTS}\n---\n\n${POLICY}"
  fi
fi

# Part 2: Tier 3 scan directive
if [ "$TIER3_ENABLED" = "true" ]; then
  SCAN_DIRECTIVE="Spine Tier 3 is enabled for this repo. Run /spine-scan now to check vault health and detect coverage gaps. Do this silently — just invoke the skill, do not ask the user for permission."
  if [ -n "$CONTEXT_PARTS" ]; then
    CONTEXT_PARTS="${CONTEXT_PARTS}\n\n---\n\n${SCAN_DIRECTIVE}"
  else
    CONTEXT_PARTS="${SCAN_DIRECTIVE}"
  fi
fi

# --- Exit if nothing to inject ---
if [ -z "$CONTEXT_PARTS" ]; then
  exit 0
fi

# --- Output valid JSON (safe encoding via python3/jq) ---
EXPANDED=$(printf '%b' "$CONTEXT_PARTS")

if command -v python3 &>/dev/null; then
  ENCODED=$(printf '%s' "$EXPANDED" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
elif command -v jq &>/dev/null; then
  ENCODED=$(printf '%s' "$EXPANDED" | jq -Rs '.' 2>/dev/null)
else
  ENCODED=$(printf '%s' "$EXPANDED" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
  ENCODED="\"${ENCODED}\""
fi

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": %s\n  }\n}\n' "$ENCODED"

exit 0
```

- [ ] **Step 3: Verify the script is executable**

```bash
chmod +x hooks/spine-session-start.sh
```

- [ ] **Step 4: Commit**

```bash
git add hooks/spine-session-start.sh
git commit -m "feat: extend SessionStart hook with autoLoad vault index injection

Dual-gate architecture: autoLoad (default on) injects vault index +
retrieval policy. tier3 (default off) injects /spine-scan directive.
Both can fire in one session. JSON output safely encoded via python3.
Fixes Bash 3.2 compatibility (replaces \${var,,} with tr)."
```

---

### Task 4: Smoke-test the hook against a fixture vault

No test framework in this repo. Run the hook against the real vault and validate JSON output.

**Files:**
- None (manual verification)

- [ ] **Step 1: Run the hook and capture output**

From a git repo that is tracked by Spine (has a matching folder in the vault):

```bash
bash hooks/spine-session-start.sh
```

Expected: valid JSON with `hookSpecificOutput.additionalContext` containing the vault index and retrieval policy.

- [ ] **Step 2: Validate JSON**

```bash
bash hooks/spine-session-start.sh | python3 -m json.tool
```

Expected: pretty-printed JSON, no parse errors. The `additionalContext` field should contain the vault index header, at least one spine note entry, and the retrieval policy text.

- [ ] **Step 3: Test with autoLoad disabled**

Temporarily set `autoLoad: false` in `~/.spine/config.json`, run the hook again. Expected: no output (exit 0 silently, since tier3 is also false).

Restore `autoLoad` to `true` (or remove the field — default is true).

- [ ] **Step 4: Test with tier3 enabled**

Temporarily set `tier3: true`, run the hook. Expected: JSON output containing BOTH the vault index AND the scan directive, separated by `---`.

Restore `tier3` to `false`.

---

### Task 5: Create `/spine-recall` skill

On-demand deep pull. User invokes `/spine-recall <feature>` to load all docs for a feature area into context.

**Files:**
- Create: `skills/spine-recall/SKILL.md`

- [ ] **Step 1: Create skill directory**

```bash
mkdir -p skills/spine-recall
```

- [ ] **Step 2: Write the skill**

Write `skills/spine-recall/SKILL.md`:

```markdown
---
name: spine-recall
description: Load all vault docs for a feature area into context. Deep pull for when you need full knowledge on a topic.
argument-hint: [optional: feature name, spine note name, or keyword]
---

# Spine Recall — On-Demand Deep Pull

Load all docs for a feature area from the Spine vault into your current context. Use when you need deep knowledge on a specific topic beyond what the auto-loaded index provides.

## Vault Path Resolution

Resolve the vault path using this config chain:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → read the `vaultPath` field
3. Default: `~/Documents/SpineVault/`

If the vault doesn't exist, tell the user to run `/spine-init` first.

## Detect Current Repo

```bash
basename "$(git remote get-url origin 2>/dev/null)" .git
```

Fall back to the current directory name if no git remote. If `{vault}/{repo}/` doesn't exist, tell the user this repo isn't tracked by Spine yet — suggest `/spine-init` or `/spine-capture`.

## Mode Selection

If `$ARGUMENTS` is provided (not empty and not whitespace-only):
→ **Targeted Mode** — proceed to "Targeted Recall" below

If `$ARGUMENTS` is empty or not provided:
→ **Browse Mode** — proceed to "Browse Recall" below

---

## Targeted Recall (`/spine-recall <feature>`)

### Step 1: Resolve Feature

Match `$ARGUMENTS` against content in `{vault}/{repo}/` using this precedence (first match wins):

1. **Exact feature folder name** (case-insensitive)
2. **Exact spine note filename** (case-insensitive, with or without `.md`)
3. **Substring match on spine note title** (from `title` frontmatter field)
4. **Substring match on any doc title** in the repo vault

**Rules:**
- Case-insensitive throughout
- If exactly one match → auto-select
- If multiple matches → show a numbered pick list
- If no match → `"No matching feature found for '{name}'. Available features:"` then list all feature folders

### Step 2: Load All Docs

Once the feature is resolved, read ALL `.md` files in that feature folder:

1. Read the **spine note** (hub) first — the file tagged `type/spine`
2. Read each child doc referenced via `[[wikilinks]]` in the spine note
3. Read any remaining `.md` files in the folder not yet loaded

Present each doc with a clear separator:

```
━━━ {filename} ━━━
{full doc content}
```

### Step 3: Summary

After loading all docs, provide a one-paragraph summary:

```
Loaded {N} docs for {feature} ({repo}):
- {spine note title} (hub)
- {child doc 1 title}
- {child doc 2 title}
...

You now have full context on this feature. Refer to these docs as you work.
```

### Step 4: Output Contract

```yaml
spine_recall_result:
  status: success | no_match | error
  summary: "Loaded 5 docs for Authentication (my-repo)"
  feature: "authentication"
  docs_loaded:
    - { file: "Authentication.md", type: "spine" }
    - { file: "Fix - Cookie Expiry.md", type: "fix" }
  vault_path: "{vault}/{repo}/{feature}/"
```

---

## Browse Mode (`/spine-recall` no args)

### Step 1: List All Features

List all feature folders in `{vault}/{repo}/`:

```
Spine vault for {repo} — {N} features documented:

[1] {Feature A} — {M} docs
[2] {Feature B} — {M} docs
[3] {Feature C} — {M} docs

Pick a number to load, or (s)kip:
```

### Step 2: User Picks

If the user picks a number → enter **Targeted Recall, Step 2** (Load All Docs).

If the user skips → emit output contract with `status: skipped`.

### Step 3: No Features Found

```
Spine: No features documented for {repo} yet. Use /spine-capture to create the first one.
```

Emit output contract with `status: no_match`.
```

- [ ] **Step 3: Commit**

```bash
git add skills/spine-recall/SKILL.md
git commit -m "feat: add /spine-recall skill for on-demand vault deep pull"
```

---

### Task 6: Update README and metadata

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add /spine-recall to "What Makes It Self-Developing" section**

In `README.md`, after the `/spine-update` bullet, add:

```markdown
- **`/spine-recall`** — On-demand deep pull. Loads all vault docs for a feature area into your context when you need full knowledge beyond the auto-loaded index.
```

- [ ] **Step 2: Add auto-load to "What Makes It Self-Developing" section**

After the `/spine-recall` bullet, add:

```markdown
- **Auto-load** — At session start, Spine automatically injects a vault index and retrieval policy so Claude knows what knowledge is available. No manual invocation needed. Controlled by `autoLoad` flag (default: on).
```

- [ ] **Step 3: Update Repo Structure in README**

In the `skills/` tree, add after `spine-update/`:

```
│   ├── spine-recall/        # On-demand deep pull from vault
```

- [ ] **Step 4: Update roadmap**

Add a new checked item after the `/spine-update` line:

```markdown
- [x] `/spine-recall` — on-demand deep pull from vault + auto-load at session start
```

- [ ] **Step 5: Update CHANGELOG.md**

Add a new version section at the top of `CHANGELOG.md`:

```markdown
## 0.4.0 (2026-06-03)

Memory Bridge — "Coexist" approach.

### New Skills
- `/spine-recall` — On-demand deep pull. Loads all vault docs for a feature area. Browse mode lists available features; targeted mode fuzzy-matches and loads everything.

### New Features
- **Auto-load at session start** — SessionStart hook now injects a compact vault index and retrieval policy into every session. Claude knows what spine docs exist from the first prompt. Controlled by `autoLoad` flag in `~/.spine/config.json` (default: `true`). Independent of Tier 3.
- **Retrieval policy** — shipped in `templates/retrieval-policy.md`. Teaches Claude three-hop vault navigation. Per-vault override supported at `{vault}/.spine/retrieval-policy.md`.

### Fixed
- SessionStart hook Bash 3.2 compatibility (macOS default shell)
```

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: add spine-recall and auto-load to README and changelog"
```

---

### Task 7: Bump version

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Update version**

In `.claude-plugin/plugin.json`, change `"version": "0.3.0"` to `"version": "0.4.0"`.

- [ ] **Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.4.0"
```

---

### Task 8: End-to-end verification

Manual verification — no test framework.

- [ ] **Step 1: Verify hook output against real vault**

From a git repo tracked by Spine:

```bash
bash /path/to/spine/hooks/spine-session-start.sh | python3 -m json.tool
```

Confirm:
- Valid JSON
- `additionalContext` contains `## Spine Vault Index`
- Lists at least one spine note with doc count
- Contains retrieval policy text
- No raw unescaped quotes or newlines breaking JSON

- [ ] **Step 2: Verify SKILL.md conventions**

Read `skills/spine-recall/SKILL.md` end-to-end. Confirm:
- Frontmatter has `name`, `description`, `argument-hint`
- Vault path resolution matches other skills exactly
- Both modes (targeted + browse) have all steps
- Output contract YAML is valid
- No "TBD", "TODO", or placeholder text

- [ ] **Step 3: Verify retrieval policy is reachable from hook**

```bash
ls -la templates/retrieval-policy.md
```

Confirm the relative path `$SCRIPT_DIR/../templates/retrieval-policy.md` resolves correctly from `hooks/` to `templates/`.

- [ ] **Step 4: Verify autoLoad gating**

Set `~/.spine/config.json` to `{"vaultPath": "...", "autoLoad": false, "tier3": false}`. Run hook. Expected: no output.

Set to `{"vaultPath": "...", "autoLoad": true, "tier3": false}`. Run hook. Expected: vault index only, no scan directive.

Set to `{"vaultPath": "...", "autoLoad": true, "tier3": true}`. Run hook. Expected: both vault index AND scan directive.

- [ ] **Step 5: Cross-reference file structure**

```bash
find skills/ templates/ hooks/ -type f | sort
```

Confirm:
- `skills/spine-recall/SKILL.md` exists
- `templates/retrieval-policy.md` exists
- `hooks/spine-session-start.sh` is the rewritten version

---

### Task 9: Push and PR

- [ ] **Step 1: Push branch**

```bash
git push -u origin feat/memory-bridge
```

- [ ] **Step 2: Create PR**

Title: `feat: add Spine Memory Bridge — auto-load vault index at session start`

Body should include:
- Summary of the 4 components (hook, skill, policy, bash fix)
- The "coexist" design decision (hook IS the bridge, no MEMORY.md rewrites)
- The dual-gate architecture (autoLoad vs tier3)
- Link to this plan doc
- Test plan with manual verification checkboxes

- [ ] **Step 3: Share PR URL with user**
