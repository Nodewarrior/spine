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

## Mode Selection

If `$ARGUMENTS` is provided (not empty and not whitespace-only):
→ **Targeted Mode** — proceed to "Targeted Mode" section below

If `$ARGUMENTS` is empty or not provided:
→ **Auto-Detect Mode** — proceed to "Auto-Detect Mode" section below

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

### Step 2: Read Existing Doc

Load the full content of the resolved doc. Extract:

1. **Staleness date:** Read `last_updated` from frontmatter. If not present, fall back to `date` field. If neither exists, treat as unknown — skip git-driven context in Step 3.

2. **Referenced files:** Parse the `**Files changed:**` section as a markdown unordered list (one file path per `- ` line). If the section is missing or unparseable, fall back to listing all non-`.md` files in the doc's parent feature folder:
   ```bash
   find {vault}/{repo}/{feature}/ -type f ! -name "*.md" 2>/dev/null
   ```
   Note: This fallback is rarely needed — most docs created by `/spine-capture` include the section.

3. **Existing wikilinks:** Scan for the `## See Also` section and collect all `[[...]]` wikilinks already present.

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

### Step 4: Draft Append Section

Draft an update section to append to the existing doc:

````markdown
---

## Update — {YYYY-MM-DD HH:MM}

> [!note] {One-line summary of what changed}
> {2-3 sentence description combining git changes and session reasoning}

**Context:** {Detailed explanation of what changed and why — include code snippets where they add value}

**New files:** {list any files introduced since last update, or omit this line entirely if none}
````

**Merge rules — follow these strictly:**
- Do NOT create a new `## See Also` section in the update block. Instead, note any new `[[wikilinks]]` to be inserted into the existing `## See Also` section at the bottom of the doc. If no `## See Also` section exists yet, one will be created at the very end of the doc in Step 6.
- Do NOT add a `**Files changed:**` block in the update section. The original `**Files changed:**` in the doc header is the canonical list and stays unchanged. Only include `**New files:**` if the work introduced source files not in the original list.
- Update header includes time (`HH:MM`) to disambiguate multiple updates on the same calendar day.

### Step 5: Present for Review

Show the user:
1. The existing doc content (first 30 lines, then `...` if the doc is longer)
2. The proposed append section in full
3. Any new wikilinks that will be added to `See Also`

Ask: **(S)ave, (E)dit, or S(k)ip?**

- **Save** → proceed to Step 6
- **Edit** → show the full draft, let the user request specific changes, apply them, then re-present with the same Save/Edit/Skip choice
- **Skip** → exit without saving. Emit output contract with `status: skipped`

### Step 6: Save

**Before writing:** Record the file's mtime and size when you first read it (Step 2). Now, before writing, re-check both values. If either has changed, abort with: `"File was modified by another process during this update. Please try /spine-update again."` Emit output contract with `status: error` and `recovery_hint: "File conflict — retry"`. This conflict guard applies to every file write in this step (doc and spine note).

After conflict guard passes:

1. **Append** the update section to the end of the existing doc file (insert the update before any existing `## See Also` section — the update goes between the last content section and See Also)
2. **Merge wikilinks** — insert any new `[[wikilinks]]` into the existing `## See Also` section. If no `## See Also` section exists, create one at the very end of the doc after the appended update
3. **Update frontmatter** — add or update `last_updated: {YYYY-MM-DD}` in the doc's YAML frontmatter. Preserve the original `date` field unchanged
4. **Spine note update** (conditional):
   - If the updated doc is NOT a spine note (i.e., it is a leaf doc inside a feature folder): check if new wikilinks were added that the spine note should reference. If so, update the spine note. Set `spine_updated: true` in output contract
   - If the updated doc IS a spine note: skip this step entirely — no circular self-reference. Set `spine_updated: false`
5. **Curator log** — ensure `{vault}/.spine/curator-log.md` exists (create from `templates/curator-log.md` if missing). Prepend this entry (newest at top):
   ```markdown
   ## {YYYY-MM-DD} — Update
   - **Updated:** `{filename}` — {N} commits incorporated
   ```
6. **Confirm** — tell the user the doc is updated and where to find it in Obsidian

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

If the user picks a number → load that doc and enter **Targeted Mode, Step 2** (Read Existing Doc) onward. The target is already resolved from the pick list — skip Step 1.

If the user skips → emit output contract with `status: skipped`.

### Step 5: No Stale Docs Found

If no docs meet the 3-commit threshold:
```
Spine: All docs up to date. Nothing to update.
```

Emit output contract with `status: no_candidates`.

---

## Output Contract

After completing an update (or determining there is nothing to update), emit a structured observation block:

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
