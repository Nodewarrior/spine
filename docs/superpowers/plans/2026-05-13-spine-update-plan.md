# /spine-update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `/spine-update` skill — a standalone Spine skill that appends timestamped update sections to existing spine docs, with targeted and auto-detect modes.

**Architecture:** Single SKILL.md file following existing Spine skill conventions. No hooks, no shell scripts, no dependencies. The skill is pure markdown instructions that Claude Code follows at invocation time. Supporting changes to README and plugin metadata.

**Tech Stack:** Markdown (SKILL.md), shell commands (git log, git diff), Obsidian frontmatter (YAML)

**Design Spec:** `docs/superpowers/specs/2026-05-13-spine-update-design.md`

---

### Task 1: Create SKILL.md — Frontmatter and Vault Resolution

**Files:**
- Create: `skills/spine-update/SKILL.md`

- [ ] **Step 1: Create skill directory and frontmatter**

```bash
mkdir -p skills/spine-update
```

Write the opening of `skills/spine-update/SKILL.md`:

```markdown
---
name: spine-update
description: Resume and enrich existing spine docs after continued work sessions. Supports targeted updates and auto-detection of stale docs.
argument-hint: [optional: spine note name, doc name, or feature name]
---

# Spine Update — Resume and Enrich Existing Docs

Update existing Spine Architecture docs with new context from continued work sessions. Appends timestamped update sections — never overwrites or deletes existing content.

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

Fall back to the current directory name if no git remote. If `{vault}/{repo}/` doesn't exist, tell the user this repo isn't tracked by Spine yet — suggest `/spine-init` or `/spine-capture` to set it up.
```

- [ ] **Step 2: Verify frontmatter matches existing skill conventions**

Compare against `skills/spine-capture/SKILL.md` lines 1-4 for format consistency. Confirm:
- `name`, `description`, `argument-hint` fields present
- Description is one sentence
- argument-hint uses `[optional: ...]` format

- [ ] **Step 3: Commit**

```bash
git add skills/spine-update/SKILL.md
git commit -m "feat: scaffold spine-update skill with vault resolution"
```

---

### Task 2: Write Mode Selection Logic

**Files:**
- Modify: `skills/spine-update/SKILL.md`

- [ ] **Step 1: Add mode routing section**

Append to `skills/spine-update/SKILL.md`:

```markdown
## Mode Selection

If `$ARGUMENTS` is provided (not empty and not whitespace-only):
→ **Targeted Mode** — proceed to "Targeted Mode" section below

If `$ARGUMENTS` is empty or not provided:
→ **Auto-Detect Mode** — proceed to "Auto-Detect Mode" section below
```

- [ ] **Step 2: Commit**

```bash
git add skills/spine-update/SKILL.md
git commit -m "feat: add mode selection logic to spine-update"
```

---

### Task 3: Write Targeted Mode — Steps 1-3 (Resolve, Read, Gather)

**Files:**
- Modify: `skills/spine-update/SKILL.md`

- [ ] **Step 1: Add target resolution section**

Append to `skills/spine-update/SKILL.md`:

```markdown
---

## Targeted Mode (`/spine-update <name>`)

### Step 1: Resolve Target

Match `$ARGUMENTS` against docs in `{vault}/{repo}/` using this precedence (first match wins):

1. **Exact filename match** (case-insensitive, with or without `.md` extension)
2. **Exact feature folder name match** → resolves to the spine note in that folder (e.g., `/spine-update auth` matches `{vault}/{repo}/auth/auth.md`)
3. **Substring match on doc title** (from `title` frontmatter field)
4. **Substring match on filename**

**Rules:**
- Case-insensitive throughout
- If exactly one match at any precedence level → auto-select that doc
- If multiple matches at the same precedence level → show a numbered pick list and let the user choose
- If no match at any level → tell user "No matching doc found for '{name}'. Did you mean to create a new doc? Try `/spine-capture`."
```

- [ ] **Step 2: Add read existing doc section**

```markdown
### Step 2: Read Existing Doc

Load the full content of the resolved doc. Extract:

1. **Staleness date:** Read `last_updated` from frontmatter. If not present, fall back to `date` field. If neither exists, treat as unknown — skip git-driven context in Step 3.

2. **Referenced files:** Parse the `**Files changed:**` section as a markdown unordered list (one file path per `- ` line). If the section is missing or unparseable, fall back to listing all `.md`-excluded files in the doc's parent feature folder:
   ```bash
   find {vault}/{repo}/{feature}/ -type f ! -name "*.md" 2>/dev/null
   ```
   Note: This fallback is rarely needed — most docs created by `/spine-capture` include the section.

3. **Existing wikilinks:** Scan for `## See Also` section and collect all `[[...]]` wikilinks already present.
```

- [ ] **Step 3: Add gather context section**

```markdown
### Step 3: Gather Update Context

Merge two sources of context:

**Git-driven context:**
If a staleness date was found in Step 2:
```bash
git log --oneline --since="{staleness_date}" -- {file1} {file2} ...
```
For commits found, read the diffs to understand what changed:
```bash
git diff {hash}~1 {hash} -- {files}
```
If no staleness date was available, skip git context entirely.

**Session-driven context:**
Summarize the current conversation's context that is relevant to this doc:
- Decisions made during this session
- Trade-offs discussed
- Work completed or planned
- Changes to the approach described in the doc

If no conversation context is relevant to this doc, omit the session block from the draft.

**Empty context guard:** If both git context and session context are empty, inform the user:
`"No new commits or session context to incorporate into '{doc name}'. Nothing to update."`
Exit without presenting a draft. Emit output contract with `status: no_candidates`.
```

- [ ] **Step 4: Commit**

```bash
git add skills/spine-update/SKILL.md
git commit -m "feat: add targeted mode steps 1-3 (resolve, read, gather)"
```

---

### Task 4: Write Targeted Mode — Steps 4-6 (Draft, Review, Save)

**Files:**
- Modify: `skills/spine-update/SKILL.md`

- [ ] **Step 1: Add draft append section**

Append to `skills/spine-update/SKILL.md` (note: the template inside uses a fenced code block — use 4-backtick fence for the outer block):

````markdown
### Step 4: Draft Append Section

Draft an update section to append to the existing doc:

```markdown
---

## Update — {YYYY-MM-DD HH:MM}

> [!note] {One-line summary of what changed}
> {2-3 sentence description combining git changes and session reasoning}

**Context:** {Detailed explanation of what changed and why — include code snippets where they add value}

**New files:** {list any files introduced since last update, or omit this line entirely if none}
```

**Merge rules — follow these strictly:**
- Do NOT create a new `## See Also` section in the update block. Instead, note any new `[[wikilinks]]` to be inserted into the existing `## See Also` section at the bottom of the doc. If no `See Also` section exists yet, one will be created at the very end of the doc in Step 6.
- Do NOT add a `**Files changed:**` block in the update section. The original `**Files changed:**` in the doc header is the canonical list and stays unchanged. Only include `**New files:**` if the work introduced source files not in the original list.
- Update header includes time (`HH:MM`) to disambiguate multiple updates on the same calendar day.
````

- [ ] **Step 2: Add present for review section**

```markdown
### Step 5: Present for Review

Show the user:
1. The existing doc content (first 30 lines, then `...` if the doc is longer)
2. The proposed append section in full
3. Any new wikilinks that will be added to `See Also`

Ask: **(S)ave, (E)dit, or S(k)ip?**

- **Save** → proceed to Step 6
- **Edit** → show the full draft, let the user request specific changes, apply them, then re-present with the same Save/Edit/Skip choice
- **Skip** → exit without saving. Emit output contract with `status: skipped`
```

- [ ] **Step 3: Add save section**

```markdown
### Step 6: Save

**Before writing:** Record the file's mtime and size when you first read it (Step 2). Now, before writing, re-check both values. If either has changed, abort with: `"File was modified by another process during this update. Please try /spine-update again."` Emit output contract with `status: error` and `recovery_hint: "File conflict — retry"`. This conflict guard applies to every file write in this step (doc and spine note).

After conflict guard passes:

1. **Append** the update section to the end of the existing doc file (before any `## See Also` section if one exists — the update goes between the last content section and See Also)
2. **Merge wikilinks** — insert any new `[[wikilinks]]` into the existing `## See Also` section. If no `## See Also` section exists, create one at the very end of the doc after the appended update
3. **Update frontmatter** — add or update `last_updated: {YYYY-MM-DD}` in the doc's YAML frontmatter. Preserve the original `date` field unchanged
4. **Spine note update** (conditional):
   - If the updated doc is NOT a spine note (i.e., it's a leaf doc inside a feature folder): check if new wikilinks were added that the spine note should reference. If so, update the spine note. Set `spine_updated: true` in output contract
   - If the updated doc IS a spine note: skip this step entirely — no circular self-reference. Set `spine_updated: false`
5. **Curator log** — ensure `{vault}/.spine/curator-log.md` exists (create from `templates/curator-log.md` if missing). Prepend:
   ```markdown
   ## {YYYY-MM-DD} — Update
   - **Updated:** `{filename}` — {N} commits incorporated
   ```
6. **Confirm** — tell the user the doc is updated and where to find it in Obsidian
```

- [ ] **Step 4: Commit**

```bash
git add skills/spine-update/SKILL.md
git commit -m "feat: add targeted mode steps 4-6 (draft, review, save)"
```

---

### Task 5: Write Auto-Detect Mode

**Files:**
- Modify: `skills/spine-update/SKILL.md`

- [ ] **Step 1: Add auto-detect mode section**

Append to `skills/spine-update/SKILL.md`:

````markdown
---

## Auto-Detect Mode (`/spine-update` no args)

### Step 1: Scan for Stale Docs

For each `.md` file in `{vault}/{repo}/` and its subfolders:

1. Read `last_updated` from frontmatter. If not present, fall back to `date`. If neither field exists, skip this doc (cannot determine staleness)
2. Parse the `**Files changed:**` section as a markdown unordered list (one path per `- ` line). If missing, use all non-`.md` files in the doc's parent folder as the file list
3. For each referenced file, count commits since the staleness date:
   ```bash
   git log --oneline --since="{last_updated or date}" -- {filepath}
   ```
4. Sum the commit counts across all referenced files
5. Flag docs with **3 or more** total commits since the staleness date

### Step 2: Rank and Cap Results

Sort flagged docs by total commit count, descending (most stale first). Cap the list at **10 results**.

### Step 3: Present Pick List

If stale docs were found:

```
Spine: {N} docs may need updating:

[1] {doc title} ({feature}/) — {N} commits since last updated
[2] {doc title} ({feature}/) — {N} commits since last updated
[3] {doc title} ({feature}/) — {N} commits since last updated

Pick a number to update, or (s)kip all:
```

If more than 10 stale docs exist, add: `(showing top 10 of {total} stale docs)`

### Step 4: User Picks

If the user picks a number → load that doc and enter **Targeted Mode, Step 2** (Read Existing Doc) onward.

If the user skips → emit output contract with `status: skipped`.

### Step 5: No Stale Docs Found

If no docs meet the 3-commit threshold:
```
Spine: All docs up to date. Nothing to update.
```

Emit output contract with `status: no_candidates`.
````

- [ ] **Step 2: Commit**

```bash
git add skills/spine-update/SKILL.md
git commit -m "feat: add auto-detect mode to spine-update"
```

---

### Task 6: Write Output Contract

**Files:**
- Modify: `skills/spine-update/SKILL.md`

- [ ] **Step 1: Add output contract section**

Append to `skills/spine-update/SKILL.md`:

````markdown
---

## Output Contract

After completing an update (or determining there's nothing to update), emit a structured observation block:

```yaml
spine_update_result:
  status: success | skipped | no_candidates | error
  summary: "Updated 'Plan - Migration Strategy' with 7 commits of context"
  updated:
    - { file: "Plan - Migration Strategy.md", feature: "auth", commits_incorporated: 7, spine_updated: true }
  next_actions:
    - { action: "review in Obsidian", path: "{vault}/repo/auth/Plan - Migration Strategy.md" }
  recovery_hint: null
```

**Status values:**
- `success` — doc updated and saved
- `skipped` — user chose not to save (declined or skipped in review)
- `no_candidates` — auto-detect found no stale docs, or empty context guard triggered in targeted mode
- `error` — write failure, vault missing, conflict guard triggered — include `recovery_hint`

**`spine_updated` field:** `true` when new wikilinks were added to the corresponding spine note (hub). `false` when no spine note changes were needed, or when the updated doc itself is a spine note.

**Cross-skill:** All Spine skills use `last_updated` (falling back to `date`) for staleness queries. `/spine-health` stale doc findings naturally align with auto-detect mode. No handoff file needed — both skills scan fresh on demand.
````

- [ ] **Step 2: Commit**

```bash
git add skills/spine-update/SKILL.md
git commit -m "feat: add output contract to spine-update"
```

---

### Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add spine-update to "What Makes It Self-Developing" section**

In `README.md`, after the `/spine-health` bullet in the "What Makes It Self-Developing" section, add:

```markdown
- **`/spine-update`** — Resume and enrich existing docs after continued work sessions. Detects stale docs or targets a specific note, then appends a timestamped update with git changes and session context. Your docs evolve with your code.
```

- [ ] **Step 2: Update Repo Structure section**

In the `Repo Structure` section, update the `skills/` tree to include:

```
│   ├── spine-update/       # Resume and update existing docs
```

Add it after `spine-scan/` in the tree.

- [ ] **Step 3: Mark roadmap item as done**

Change the roadmap line from:
```markdown
- [ ] `/spine-update` — resume and enrich existing spine docs (plans, architecture) after continued work sessions
```
to:
```markdown
- [x] `/spine-update` — resume and enrich existing spine docs (plans, architecture) after continued work sessions
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add spine-update to README"
```

---

### Task 8: Verification

No automated tests — Spine skills are markdown instructions executed by Claude Code at runtime.

- [ ] **Step 1: Verify SKILL.md structure matches conventions**

Read `skills/spine-update/SKILL.md` end-to-end. Confirm:
- Frontmatter has `name`, `description`, `argument-hint`
- Vault path resolution section matches other skills exactly
- All 6 targeted mode steps present and numbered correctly
- Auto-detect mode has all 5 steps
- Output contract YAML is valid
- No "TBD", "TODO", or placeholder text
- All edge cases from design spec are covered

- [ ] **Step 2: Cross-reference against design spec**

Open `docs/superpowers/specs/2026-05-13-spine-update-design.md`. Verify:
- Every design decision reflected in skill
- Every edge case from spec's table has handling in skill
- Merge rules match exactly
- Conflict guard described in save step
- `last_updated` vs `date` behavior matches spec
- Spine note self-update exclusion present

- [ ] **Step 3: Verify cross-references are accurate**

Confirm:
- `templates/curator-log.md` exists at that path
- Config chain matches other skills
- Output contract field names consistent with other skills' contracts

- [ ] **Step 4: Fix commit if needed**

```bash
git add -A
git commit -m "fix: address verification findings in spine-update"
```

Only if fixes were needed. Skip if clean.

---

### Task 9: Push and PR

- [ ] **Step 1: Push branch**

```bash
git push -u origin feat/spine-update
```

- [ ] **Step 2: Create PR**

Title: `feat: add /spine-update skill`

Body should include: summary of the skill, origin (Victor's feedback), link to design spec, and test plan with manual verification checkboxes.

- [ ] **Step 3: Share PR URL with user**
