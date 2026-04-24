# Tier 3 Curator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve Spine into a self-maintaining system with session-start scanning, silent commit tracking, and batch capture at session end.

**Architecture:** Two new skills (`/spine-scan`, enhanced `/spine-capture --batch`) + one new shell script (`spine-commit-tracker.sh`) + updated hooks config. All state stored as JSON/markdown in the vault's `.spine/` directory. Zero new dependencies.

**Tech Stack:** Bash shell scripts, SKILL.md prompt files, JSON state files, Markdown

**Spec:** `docs/specs/2026-04-19-tier3-curator-design.md`

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `skills/spine-scan/SKILL.md` | Session-start scanner — auto-fixes, gap detection, banner |
| Create | `hooks/spine-commit-tracker.sh` | Silent commit tracker — appends to pending-commits.json |
| Create | `templates/curator-log.md` | Template for the audit log |
| Modify | `skills/spine-capture/SKILL.md` | Add `--batch` mode for session-end batch capture |
| Modify | `hooks/hooks.json` | Add SessionStart and Stop hooks |
| Delete | `hooks/spine-commit-check.sh` | Replaced by spine-commit-tracker.sh |
| Modify | `.claude-plugin/plugin.json` | Bump version to 0.2.0 |
| Modify | `CHANGELOG.md` | Document Tier 3 changes |
| Modify | `README.md` | Update roadmap, add Tier 3 documentation |

---

### Task 1: Create the Curator Log Template

**Files:**
- Create: `templates/curator-log.md`

- [ ] **Step 1: Create the template file**

```markdown
# Curator Log

<!-- Spine Tier 3 — append-only audit trail. Newest entries at top. -->
<!-- Each session scan and batch capture appends a dated section here. -->
```

- [ ] **Step 2: Verify the file exists and is valid markdown**

Run: `cat templates/curator-log.md`
Expected: The template content above, valid markdown.

- [ ] **Step 3: Commit**

```bash
git add templates/curator-log.md
git commit -m "feat: add curator log template for Tier 3 audit trail"
```

---

### Task 2: Create the Post-Commit Tracker Script

**Files:**
- Create: `hooks/spine-commit-tracker.sh`
- Reference: `hooks/spine-resolve-vault.sh` (unchanged, used for vault resolution)
- Reference: `hooks/spine-commit-check.sh` (the script we're replacing — study for significance filter logic)

- [ ] **Step 1: Create `spine-commit-tracker.sh`**

```bash
#!/bin/bash
# Spine Architecture — post-commit tracker (Tier 3)
# Silently records significant commits to pending-commits.json.
# Replaces spine-commit-check.sh (which printed nudge messages).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve vault path
VAULT_PATH=$(bash "$SCRIPT_DIR/spine-resolve-vault.sh" 2>/dev/null)

# If no vault configured, exit silently
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

# Detect repo name
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null)
if [ -z "$REPO_NAME" ]; then
  REPO_NAME=$(basename "$(pwd)")
fi

# Only track repos that have a folder in the vault
if [ ! -d "$VAULT_PATH/$REPO_NAME" ]; then
  exit 0
fi

# Get the latest commit stats
COMMIT_HASH=$(git log -1 --pretty=%h 2>/dev/null)
COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null)
COMMIT_TIMESTAMP=$(git log -1 --pretty=%aI 2>/dev/null)
CHANGED_FILES_LIST=$(git diff --name-only HEAD~1 HEAD 2>/dev/null)
CHANGED_FILES_COUNT=$(echo "$CHANGED_FILES_LIST" | wc -l | tr -d '[:space:]')
INSERTIONS=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
DELETIONS=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

INSERTIONS=${INSERTIONS:-0}
DELETIONS=${DELETIONS:-0}
TOTAL_CHANGES=$((INSERTIONS + DELETIONS))

# Significance filter — skip trivial commits
if [ "$TOTAL_CHANGES" -lt 20 ] && [ "$CHANGED_FILES_COUNT" -le 1 ]; then
  exit 0
fi

# Skip merge commits
if echo "$COMMIT_MSG" | grep -qiE '^merge'; then
  exit 0
fi

# Skip style/lint/chore/docs commits
if echo "$COMMIT_MSG" | grep -qiE '^(style|lint|chore|docs):'; then
  exit 0
fi

# Ensure .spine directory exists
SPINE_DIR="$VAULT_PATH/.spine"
mkdir -p "$SPINE_DIR"

PENDING_FILE="$SPINE_DIR/pending-commits.json"

# Convert file list to JSON array
FILES_JSON="["
FIRST=true
while IFS= read -r file; do
  if [ -n "$file" ]; then
    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      FILES_JSON="$FILES_JSON,"
    fi
    FILES_JSON="$FILES_JSON\"$file\""
  fi
done <<< "$CHANGED_FILES_LIST"
FILES_JSON="$FILES_JSON]"

# Build the commit JSON entry
COMMIT_ENTRY=$(cat <<ENTRY_EOF
{
    "hash": "$COMMIT_HASH",
    "message": "$COMMIT_MSG",
    "files": $FILES_JSON,
    "insertions": $INSERTIONS,
    "deletions": $DELETIONS,
    "timestamp": "$COMMIT_TIMESTAMP",
    "repo": "$REPO_NAME"
  }
ENTRY_EOF
)

# Append to pending-commits.json
# If file exists and has commits, append to the array. Otherwise create new.
if [ -f "$PENDING_FILE" ] && command -v python3 &>/dev/null; then
  python3 -c "
import json, sys
try:
    with open('$PENDING_FILE', 'r') as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    data = {'commits': []}
entry = json.loads('''$COMMIT_ENTRY''')
data['commits'].append(entry)
with open('$PENDING_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
elif [ -f "$PENDING_FILE" ] && command -v node &>/dev/null; then
  node -e "
const fs = require('fs');
let data;
try { data = JSON.parse(fs.readFileSync('$PENDING_FILE', 'utf8')); }
catch { data = { commits: [] }; }
data.commits.push(JSON.parse(\`$COMMIT_ENTRY\`));
fs.writeFileSync('$PENDING_FILE', JSON.stringify(data, null, 2));
" 2>/dev/null
else
  # No existing file or no JSON parser — create fresh
  echo "{\"commits\":[$COMMIT_ENTRY]}" > "$PENDING_FILE"
fi

# Silent — no output
exit 0
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x hooks/spine-commit-tracker.sh`

- [ ] **Step 3: Verify the script is syntactically valid**

Run: `bash -n hooks/spine-commit-tracker.sh`
Expected: No output (no syntax errors).

- [ ] **Step 4: Commit**

```bash
git add hooks/spine-commit-tracker.sh
git commit -m "feat: add silent post-commit tracker for Tier 3"
```

---

### Task 3: Create the `/spine-scan` Skill

**Files:**
- Create: `skills/spine-scan/SKILL.md`

- [ ] **Step 1: Create the skill file**

```markdown
---
name: spine-scan
description: Session-start vault scanner. Auto-fixes broken wikilinks, missing tags, and orphan docs. Detects coverage gaps from recent commits. Runs automatically at session start.
---

# Spine Scan — Session-Start Vault Scanner

Automatically scan the Spine vault for decay and coverage gaps. Auto-fixes low-risk issues, reports findings as a non-blocking banner.

## Vault Path Resolution

Resolve the vault path using this config chain:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → read the `vaultPath` field
3. Default: `~/Documents/SpineVault/`

If no vault is found, or the vault directory doesn't exist, **skip silently**. Not every repo uses Spine.

## Detect Current Repo

```bash
basename "$(git remote get-url origin 2>/dev/null)" .git
```

Fall back to the current directory name if no git remote. If `{vault}/{repo}/` doesn't exist, skip silently — this repo isn't tracked by Spine.

## Phase 1: Auto-Fixes

Scan the vault for mechanical issues and fix them silently. Log every action to `{vault}/.spine/curator-log.md`.

Ensure `{vault}/.spine/` directory exists before writing.

### 1a. Broken Wikilinks

For each markdown file in `{vault}/{repo}/`:
1. Find all `[[wikilinks]]` in the file content
2. Check if each linked note exists anywhere in the vault (search by filename without extension)
3. If a linked note doesn't exist:
   - Search for notes with similar names (typos, renamed docs)
   - If a close match is found, update the wikilink to the correct name
   - If no match, remove the broken wikilink and log it
4. Log: `**Auto-fixed:** Broken wikilink in \`{file}\` → \`[[{corrected}]]\``

### 1b. Missing or Wrong Type Tags

For each markdown file in `{vault}/{repo}/` (skip spine notes):
1. Read the YAML frontmatter
2. Determine the expected `type/*` tag from the filename:
   - Filename starts with date + `Fix -` → `type/fix`
   - Filename starts with date + `Feature -` → `type/feature`
   - Filename starts with `Architecture -` → `type/architecture`
   - Filename starts with `Plan -` → `type/plan`
   - Filename starts with `Decision -` → `type/decision`
3. Check if the frontmatter `tags` array contains the expected `type/*` tag
4. If missing or wrong, add/correct it in the frontmatter
5. Log: `**Auto-fixed:** Missing \`{tag}\` tag on \`{filename}\``

### 1c. Orphan Docs

For each feature folder in `{vault}/{repo}/`:
1. Find the spine note (`{Feature}.md` with `type/spine` tag)
2. List all other markdown files in the folder
3. For each file, check if it's referenced as a `[[wikilink]]` in the spine note
4. If not linked, add a wikilink under the appropriate section:
   - `type/fix` → `## Fixes`
   - `type/feature` → `## Features`
   - `type/architecture` → `## Architecture`
   - `type/plan` → `## Plans`
   - `type/decision` → `## Decisions`
5. Log: `**Auto-fixed:** Orphan doc \`{filename}\` linked into \`{spine-note}\``

### 1d. Stale Doc Detection

For each doc in `{vault}/{repo}/` that has a `**Files changed:**` section:
1. Extract the file paths listed
2. For each file path, run: `git log --oneline --since="{doc-date}" -- {filepath}`
3. If the file has 3+ commits since the doc was written, add or update a `stale: true` field in the frontmatter
4. Log: `**Flagged stale:** \`{doc}\` — \`{filepath}\` has {N} commits since doc date`

## Phase 2: Coverage Gap Detection

Find significant commits that have no corresponding Obsidian doc.

### 2a. Determine Time Window

1. Read `{vault}/.spine/last-scan-timestamp`
   - If the file doesn't exist, default to 2 weeks ago
2. Also read `{vault}/.spine/pending-commits.json` for any leftover commits from abrupt session ends

### 2b. Find Undocumented Commits

1. Run `git log --oneline --since="{last-scan-timestamp}"` in the current repo
2. Filter out trivial commits:
   - Skip commit messages matching `^(style|lint|chore|docs|merge)`
   - Skip commits with < 20 total line changes AND <= 1 file
3. Group remaining commits by feature area:
   - Match changed file paths against existing feature folders in the vault
   - Group commits touching the same feature together
4. For each group, check if a corresponding doc exists in that feature folder with a date on or after the commit date
5. Collect any groups with no matching doc as coverage gaps

## Phase 3: Banner

Print a single non-blocking summary. Do NOT ask for input or wait for a response.

Format:
```
🦴 Spine: {N} commits since last session — {fixes summary} (auto). {gaps summary}.
```

Examples:
- `🦴 Spine: 5 commits since last session — 2 wikilinks fixed, 1 tag corrected (auto). 2 coverage gaps (auth, payments). Run /spine-capture when ready.`
- `🦴 Spine: No new commits. 1 orphan doc linked (auto). Vault is healthy.`
- `🦴 Spine: 3 commits since last session. No issues found. Vault is clean.`

If there are zero commits and zero issues, either print `🦴 Spine: Vault is clean.` or skip the banner entirely.

## Phase 4: Update Timestamp

Write the current ISO timestamp to `{vault}/.spine/last-scan-timestamp`:
```
2026-04-19T14:30:00Z
```

## Curator Log Format

Append a dated section to `{vault}/.spine/curator-log.md` (create the file from `templates/curator-log.md` if it doesn't exist). Newest entries at the top of the file (prepend, don't append).

```markdown
## {YYYY-MM-DD} — Session Scan
- **Auto-fixed:** {description of each fix}
- **Flagged stale:** {description of each stale doc}
- **Coverage gap:** {description of each gap}
```

If no actions were taken, do not add an entry.
```

- [ ] **Step 2: Verify the skill file has valid YAML frontmatter**

Run: `head -5 skills/spine-scan/SKILL.md`
Expected: YAML frontmatter with `name: spine-scan` and `description`.

- [ ] **Step 3: Commit**

```bash
git add skills/spine-scan/SKILL.md
git commit -m "feat: add /spine-scan session-start scanner skill"
```

---

### Task 4: Enhance `/spine-capture` with `--batch` Mode

**Files:**
- Modify: `skills/spine-capture/SKILL.md`

- [ ] **Step 1: Read the current skill file**

Read `skills/spine-capture/SKILL.md` to confirm current content before editing.

- [ ] **Step 2: Update the frontmatter to mention batch mode**

Change the description line in the YAML frontmatter:

Old:
```yaml
description: Capture completed work (fix, feature, architecture decision, plan) as an Obsidian doc in the Spine Architecture vault. Auto-detects repo, feature, and doc type from context.
argument-hint: [optional: description of what to capture]
```

New:
```yaml
description: Capture completed work (fix, feature, architecture decision, plan) as an Obsidian doc in the Spine Architecture vault. Auto-detects repo, feature, and doc type from context. Supports --batch mode for session-end batch capture.
argument-hint: [optional: description or --batch for session-end batch mode]
```

- [ ] **Step 3: Add the Batch Mode section after the existing Step 6**

Append the following after the existing `## Step 6: Detect Patterns (Optional)` section:

```markdown

---

## Batch Mode (`--batch`)

When invoked with `$ARGUMENTS` equal to `--batch`, switch to batch capture mode. This is typically triggered automatically by the Stop hook at session end.

### Batch Step 1: Read Pending Commits

1. Resolve vault path (same config chain as above)
2. Read `{vault}/.spine/pending-commits.json`
3. If the file doesn't exist or `commits` array is empty, print:
   `🦴 Spine: No pending commits to capture. Session clean.`
   Then exit — do not proceed.

### Batch Step 2: Group by Feature

1. For each pending commit, examine the `files` array
2. Match file paths against existing feature folders in `{vault}/{repo}/`
3. Group commits that touch the same feature together
4. If a commit's files don't match any existing feature:
   - Ask the user: "Commit `{hash}` ({message}) touches `{files}`. Which feature does this belong to? (or type a new feature name)"
   - Create the feature folder and spine note if new

### Batch Step 3: Draft Docs

For each feature group:
1. Read the actual git diffs for all commits in the group:
   ```bash
   git diff {hash}~1 {hash} -- {files}
   ```
2. Consolidate into a single doc (don't create one doc per commit)
3. Classify the work: fix, feature, architecture, plan, or decision
4. Draft the doc using the same template as Step 3 above (frontmatter, callouts, code snippets, wikilinks)
5. Use the combined context from all commits for a richer description

### Batch Step 4: Present Batch for Approval

Show the user all drafted docs at once:

```
🦴 Spine: You had {N} significant commits this session:

[1] {Type} - {Description} ({Feature})
    → {N} commits consolidated
    Preview: {first 3 lines of the doc body}

[2] {Type} - {Description} ({Feature})
    → {N} commits
    Preview: {first 3 lines of the doc body}

For each: (S)ave, (E)dit, or S(k)ip?
```

Process each doc based on user choice:
- **Save** → proceed to Batch Step 5
- **Edit** → show full draft, let user request changes, then save
- **Skip** → do not save, remove from pending

### Batch Step 5: Save Approved Docs

For each approved doc:
1. Write the doc to `{vault}/{repo}/{feature}/{filename}.md`
2. Update the spine note with a `[[wikilink]]` under the appropriate section
3. Check Claude memory — if this is a new feature with no memory signpost, create one
4. Log to `{vault}/.spine/curator-log.md`:
   ```markdown
   ## {YYYY-MM-DD} — Batch Capture
   - **Saved:** `{filename}` (approved)
   ```

### Batch Step 6: Clean Up Pending

1. Remove saved and skipped commits from `{vault}/.spine/pending-commits.json`
2. If all commits processed, delete the file
3. If some commits remain (shouldn't happen normally), keep them for next session

### Batch Step 7: Summary

Print a final summary:
```
🦴 Spine: {N} docs saved, {N} skipped. Vault updated.
```
```

- [ ] **Step 4: Verify the modified skill file is well-formed**

Read the full file to check:
- YAML frontmatter is valid
- All sections are present (original Steps 1-6 + new Batch Mode section)
- No broken markdown

- [ ] **Step 5: Commit**

```bash
git add skills/spine-capture/SKILL.md
git commit -m "feat: add --batch mode to /spine-capture for session-end capture"
```

---

### Task 5: Update Hooks Configuration

**Files:**
- Modify: `hooks/hooks.json`
- Delete: `hooks/spine-commit-check.sh`

- [ ] **Step 1: Read the current hooks.json**

Read `hooks/hooks.json` to confirm current content.

- [ ] **Step 2: Replace hooks.json with the Tier 3 configuration**

Write the full updated content:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash(git commit*)",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/spine-commit-tracker.sh\""
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "skill",
            "skill": "spine-scan"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "skill",
            "skill": "spine-capture",
            "args": "--batch"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Verify JSON is valid**

Run: `python3 -m json.tool hooks/hooks.json`
Expected: Pretty-printed JSON with no errors.

- [ ] **Step 4: Delete the old nudge hook**

Run: `git rm hooks/spine-commit-check.sh`

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: upgrade hooks for Tier 3 — tracker, scan, batch capture"
```

---

### Task 6: Update Plugin Version and Documentation

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Bump version in plugin.json**

Change `"version": "0.1.0"` to `"version": "0.2.0"` in `.claude-plugin/plugin.json`.

- [ ] **Step 2: Update CHANGELOG.md**

Prepend the following above the existing `## 0.1.0` entry:

```markdown
## 0.2.0 (2026-04-19)

Tier 3: Self-Maintaining Vault.

### New Skills
- `/spine-scan` — session-start scanner with auto-fix for broken wikilinks, missing tags, orphan docs, and stale detection. Runs automatically at session start via hook.

### Enhanced Skills
- `/spine-capture --batch` — batch capture mode for session-end. Groups pending commits by feature, drafts docs, presents for approval.

### New Hooks
- `SessionStart` hook → triggers `/spine-scan` automatically
- `Stop` hook → triggers `/spine-capture --batch` at session end
- `spine-commit-tracker.sh` — silently tracks significant commits to `pending-commits.json` (replaces the nudge-style `spine-commit-check.sh`)

### New State Files
- `{vault}/.spine/pending-commits.json` — tracked commits awaiting batch capture
- `{vault}/.spine/last-scan-timestamp` — last scan time for gap detection
- `{vault}/.spine/curator-log.md` — append-only audit trail of all auto-actions

### Templates
- `curator-log.md` — template for the audit log

### Removed
- `spine-commit-check.sh` — replaced by `spine-commit-tracker.sh`
```

- [ ] **Step 3: Update README.md roadmap**

Change the Tier 3 line from:
```markdown
- [ ] Tier 3 curator agent — autonomous vault maintenance (autoResearch-inspired)
```
To:
```markdown
- [x] Tier 3 curator — self-maintaining vault with session-start scanning, silent commit tracking, and batch capture
```

- [ ] **Step 4: Update README.md "What Makes It Self-Developing" section**

Add Tier 3 features to the existing list. After the status line bullet, add:

```markdown
- **Session-start scanner** — `/spine-scan` runs automatically when you open Claude Code. Auto-fixes broken wikilinks, missing tags, and orphan docs. Detects undocumented commits and reports them in a non-blocking banner.
- **Silent commit tracking** — Every significant commit is tracked automatically. No nudges, no noise.
- **Batch capture** — At session end, `/spine-capture --batch` groups all tracked commits by feature, drafts docs, and presents them for your approval.
- **Curator log** — Every auto-action is recorded in `{vault}/.spine/curator-log.md` for full transparency.
```

- [ ] **Step 5: Update README.md repo structure**

Update the repo structure diagram to show new files:

```
spine/
├── .claude-plugin/          # Plugin metadata
├── skills/
│   ├── spine-init/          # Vault setup wizard
│   ├── spine-capture/       # Auto-draft docs (+ batch mode)
│   ├── spine-health/        # Vault audit and curation
│   └── spine-scan/          # Session-start scanner (Tier 3)
├── hooks/
│   ├── hooks.json           # SessionStart + PostToolUse + Stop hooks
│   ├── spine-commit-tracker.sh  # Silent commit tracker
│   └── spine-resolve-vault.sh   # Vault path resolver
├── templates/               # Vault templates
├── scripts/
│   └── statusline-spine.sh  # Optional status line segment
└── docs/
    ├── conventions.md       # Full naming and tagging reference
    ├── status-line.md       # Status line setup guide
    └── specs/               # Design specs
```

- [ ] **Step 6: Commit all documentation updates**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md README.md
git commit -m "docs: update version, changelog, and readme for Tier 3 release"
```

---

### Task 7: Integration Test — Full Tier 3 Flow

- [ ] **Step 1: Verify all new files exist**

Run:
```bash
ls -la skills/spine-scan/SKILL.md hooks/spine-commit-tracker.sh templates/curator-log.md
```
Expected: All three files exist.

- [ ] **Step 2: Verify deleted file is gone**

Run:
```bash
ls hooks/spine-commit-check.sh 2>&1
```
Expected: `No such file or directory`

- [ ] **Step 3: Verify hooks.json is valid and has all three hook types**

Run:
```bash
python3 -c "import json; d=json.load(open('hooks/hooks.json')); print(list(d['hooks'].keys()))"
```
Expected: `['PostToolUse', 'SessionStart', 'Stop']`

- [ ] **Step 4: Verify spine-commit-tracker.sh is executable and syntactically valid**

Run:
```bash
test -x hooks/spine-commit-tracker.sh && echo "executable" || echo "not executable"
bash -n hooks/spine-commit-tracker.sh && echo "valid syntax" || echo "syntax error"
```
Expected: `executable` and `valid syntax`

- [ ] **Step 5: Verify plugin version is 0.2.0**

Run:
```bash
python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])"
```
Expected: `0.2.0`

- [ ] **Step 6: Verify spine-capture SKILL.md contains batch mode**

Run:
```bash
grep -c "Batch Mode" skills/spine-capture/SKILL.md
```
Expected: `1` (the batch mode section header exists)

- [ ] **Step 7: Run a manual test of the commit tracker**

In a Spine-tracked repo with a configured vault:
1. Make a test change (20+ lines across 2+ files)
2. Commit via Claude Code
3. Check `{vault}/.spine/pending-commits.json` exists and contains the commit

- [ ] **Step 8: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address integration test findings"
```
Only run if fixes were needed. Skip if all tests passed.
