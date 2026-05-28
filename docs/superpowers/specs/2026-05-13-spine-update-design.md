# /spine-update — Design Spec

**Date:** 2026-05-13
**Status:** Approved (post-review hardening applied)
**Author:** Akshay Kumar
**Origin:** User feedback from Victor Joh — "I like to refer to a spine note and start a context session around that and update the existing spine document instead of having it create a new one."

---

## Problem

`/spine-capture` creates new docs. There is no way to evolve existing docs after continued work sessions. Plan and architecture docs naturally change over multiple sessions, but the only option today is to manually edit them or create a new doc that partially duplicates the old one.

## Solution

New standalone skill `/spine-update` that appends timestamped update sections to existing spine docs. Two modes: targeted (user names the doc) and auto-detect (scan for stale docs).

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Standalone vs mode on capture | Standalone skill | Different intent: capture = new docs from commits, update = evolve existing docs from continued work |
| Append vs revise | Append-only | Preserves history — doc becomes a timeline of how work evolved |
| Content source | Git changes + session context | Git grounds it in facts, session captures reasoning and decisions |
| Tier 3 gate | No gate — available to all users | User-initiated like `/spine-capture`, not autonomous |
| Date tracking | Preserve original `date`, add `last_updated` | Original date anchors doc creation; `last_updated` drives staleness queries across all skills |

---

## Skill Metadata

```yaml
name: spine-update
description: Resume and enrich existing spine docs after continued work sessions. Supports targeted updates and auto-detection of stale docs.
argument-hint: [optional: spine note name, doc name, or feature name]
```

## Vault Path & Repo Detection

Same config chain as all Spine skills:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → `vaultPath` field
3. Default: `~/Documents/SpineVault/`

Repo detection via `git remote get-url origin`, fallback to directory name. If vault or repo folder missing, tell user to run `/spine-init`.

---

## Mode 1: Targeted (`/spine-update <name>`)

### Step 1: Resolve Target

Match `<name>` against docs in `{vault}/{repo}/` using this precedence (first match wins):

1. **Exact filename match** (case-insensitive, with or without `.md` extension)
2. **Exact feature folder name match** → resolves to the spine note in that folder
3. **Substring match on doc title** (from `title` frontmatter field)
4. **Substring match on filename**

**Rules:**
- Case-insensitive throughout
- If exactly one match at any precedence level → auto-select
- If multiple matches at the same level → show pick list
- If no match at any level → tell user "No matching doc found" and suggest `/spine-capture`

### Step 2: Read Existing Doc

Load full content of the resolved doc. Extract:
- `last_updated` from frontmatter (if present); fall back to `date` field
- If neither exists, treat staleness window as unknown — skip git-driven context, rely on session context only
- `Files changed` section — parse as markdown unordered list (one path per line). If section missing or unparseable, fall back to all files in the doc's feature folder
- Current wikilinks in `See Also` section

### Step 3: Gather Update Context

Two sources, merged:

**Git-driven:** Run `git log --since="{last_updated or date}" -- {files}` for commits touching files referenced in the doc. Read diffs for substance. If no date available (Step 2 fallback), skip git context entirely.

**Session-driven:** Summarize the current conversation's relevant context — decisions made, trade-offs discussed, work completed, plans revised. Scope: use conversation history from the current session. If no conversation context is relevant to this doc, omit the session block from the draft.

**Empty context guard:** If both git context and session context are empty, inform the user: "No new commits or session context to incorporate into this doc." Exit without presenting a draft.

### Step 4: Draft Append Section

```markdown
---

## Update — {YYYY-MM-DD HH:MM}

> [!note] {One-line summary of what changed}
> {2-3 sentence description}

**Context:** {git-driven changes + session reasoning}

**New files:** {list any new files, or omit this line if none}
```

**Merge rules:**
- Do NOT add a new `## See Also` section. Instead, insert any new `[[wikilinks]]` into the existing `## See Also` section at the bottom of the doc. If no `See Also` section exists, create one at the very end (after all update sections).
- Do NOT add a new `**Files changed:**` block in the update section. The original `**Files changed:**` in the doc header remains the canonical list. Only add a `**New files:**` line in the update if the work introduced files not in the original list.
- Update headers include time (`HH:MM`) to disambiguate multiple updates on the same day.

### Step 5: Present for Review

Show user:
1. Existing doc (or first 30 lines + "..." if long)
2. Proposed append section
3. Any new wikilinks to be added to See Also

Ask: "(S)ave, (E)dit, or S(k)ip?"
- **Save** → proceed to Step 6
- **Edit** → show full draft, let user request changes, then re-present
- **Skip** → exit without saving

### Step 6: Save

1. Append update section to existing doc file
2. Merge new wikilinks into existing `See Also` section (or create one at doc end)
3. Add `last_updated: {YYYY-MM-DD}` to frontmatter (preserve original `date` field unchanged)
4. **Conflict guard before write:** Record mtime + file size before reading. Before writing, re-check both. If either changed, abort with: "File modified by another process during update. Try again." This applies to both the doc write and any spine note write.
5. If the updated doc is NOT a spine note: update the corresponding spine note with new wikilinks if needed (set `spine_updated: true` in output)
6. If the updated doc IS a spine note: skip the spine note update step (the doc itself is the hub — no circular self-update)
7. Log to curator log
8. Ensure `{vault}/.spine/curator-log.md` exists — create from `templates/curator-log.md` if missing

---

## Mode 2: Auto-Detect (`/spine-update` no args)

### Step 1: Scan for Stale Docs

For each doc in `{vault}/{repo}/` and its subfolders:
1. Read `last_updated` frontmatter (fall back to `date` if no `last_updated`)
2. If neither field exists, skip the doc (cannot determine staleness)
3. Parse `**Files changed:**` section as markdown unordered list (one path per line). If missing, use all files in the doc's feature folder
4. For each referenced file, run `git log --oneline --since="{last_updated or date}" -- {filepath}`
5. Flag docs with 3+ commits since the staleness date

### Step 2: Rank Results

Sort by commit count descending (most stale first). Cap at 10 results.

### Step 3: Present Pick List

```
Spine: 3 docs may need updating:

[1] Plan - Migration Strategy (auth/) — 7 commits since last updated
[2] Architecture - API Routes (api/) — 4 commits since last updated
[3] 2026-04-15 Feature - OAuth Flow (auth/) — 3 commits since last updated

Pick one to update, or (s)kip all:
```

If more than 10 stale docs exist, note: `(showing top 10 of {N} stale docs)`

### Step 4: User Picks

Selected doc enters targeted flow (Mode 1, Step 2 onward).

### Step 5: No Stale Docs

Print: `Spine: All docs up to date. Nothing to update.`

---

## Output Contract

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

**`spine_updated` field:** `true` when new wikilinks were added to the spine note (hub). `false` when no spine note changes were needed, or when the updated doc itself is a spine note.

**Cross-skill:** `/spine-health` stale doc findings inform auto-detect mode. No handoff file needed — both skills scan fresh on demand. All skills use `last_updated` (falling back to `date`) for staleness queries.

---

## Curator Log

After save, prepend to `{vault}/.spine/curator-log.md` (create from `templates/curator-log.md` if file doesn't exist):

```markdown
## {YYYY-MM-DD} — Update
- **Updated:** `{filename}` — {N} commits incorporated
```

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Doc has no "Files changed" section | Fall back to all files in feature folder |
| Doc has no `date` or `last_updated` | Skip git context, use session context only. In auto-detect, skip doc entirely |
| Target doc doesn't exist | Print "No matching doc found" and suggest `/spine-capture` |
| Multiple docs match at same precedence | Show pick list, don't guess |
| Obsidian editing same file | Conflict guard: check mtime + file size before write. Abort if changed |
| No git history since doc date | Use session context only. If session context also empty, exit with "nothing to incorporate" |
| Doc is a spine note (hub) | Update is valid — append works. Skip Step 6 spine note update (no circular self-reference) |
| Multiple updates same day | Headers include time (`HH:MM`) for disambiguation |
| Pick list has >10 results | Show top 10 by commit count, note total |
| Curator log doesn't exist | Create from `templates/curator-log.md` before prepending |

---

## What This Skill Does NOT Do

- Does not delete or rewrite existing content (append-only)
- Does not run autonomously (no Tier 3 gate, no hook trigger)
- Does not create new docs (that's `/spine-capture`)
- Does not modify other docs or spine notes beyond adding wikilinks
- Does not overwrite original `date` frontmatter (uses `last_updated` instead)
