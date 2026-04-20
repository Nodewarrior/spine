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
