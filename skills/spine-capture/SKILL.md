---
name: spine-capture
description: Capture completed work (fix, feature, architecture decision, plan) as an Obsidian doc in the Spine Architecture vault. Auto-detects repo, feature, and doc type from context. Supports --batch mode for session-end batch capture.
argument-hint: [optional: description or --batch for session-end batch mode]
---

# Spine Capture — Document Work to Obsidian Vault

Capture completed work into the Spine Architecture vault.

## Vault Path Resolution

Resolve the vault path using this config chain:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → read the `vaultPath` field
3. Default: `~/Documents/SpineVault/`

If the vault doesn't exist, tell the user to run `/spine-init` first.

## Doc Types and Prefixes

| Prefix | Tag | When to use |
|--------|-----|-------------|
| `Fix - {description}` | `type/fix` | Bug fix — include root cause and code snippets |
| `Feature - {description}` | `type/feature` | New functionality |
| `Architecture - {description}` | `type/architecture` | Design doc, API structure, data flow |
| `Plan - {description}` | `type/plan` | Implementation plan |
| `Decision - {description}` | `type/decision` | Decision record with context and trade-offs |

**Date prefixes:** Add `YYYY-MM-DD` prefix on Fix and Feature docs only. No date prefix on Architecture, Plan, or Decision docs.

## Step 1: Determine What to Capture

If `$ARGUMENTS` is provided, use that as the description. Otherwise:

1. Run `git log --oneline -10` and `git diff main...HEAD --stat` to see recent work
2. Read any recently modified source files to understand the change
3. Ask the user: "What type of doc is this?" (fix / feature / architecture / plan / decision) — unless obvious from context

## Step 2: Determine Repo and Feature

1. **Repo**: Detect from the git remote:
   ```bash
   basename "$(git remote get-url origin 2>/dev/null)" .git
   ```
   Fall back to the current directory name if no git remote.

2. **Feature**: Read existing spine notes at `{vault}/{repo}/` to find matching features. Match by:
   - File paths changed (which feature folder do they map to?)
   - Component names, module names
   - If no match, ask the user: "This looks like a new feature area. What should I call it?"
   - For new features, create the folder and spine note

## Step 3: Draft the Obsidian Doc

```markdown
---
title: "{Type} - {Description}"
date: {YYYY-MM-DD}
tags:
  - {repo}
  - {feature-kebab-case}
  - type/{type}
severity: {sev1|sev2|sev3} (fixes only)
status: {resolved|in-progress|pending}
---

# {Type} - {Description}

> [!bug|note|tip] {One-line summary}
> {2-3 sentence description of what happened / what was built}

**Files changed:** {list of key files}

---

## {Root Cause / Problem / Motivation}

{Detailed explanation with code snippets where helpful}

---

## {Fix / Implementation / Design}

{What was done, with code snippets showing before/after or key patterns}

---

## See Also

- [[{related spine doc 1}]]
- [[{related spine doc 2}]]
```

**Guidelines:**
- Use Obsidian callouts (`> [!bug]`, `> [!note]`, `> [!warning]`, `> [!tip]`)
- Include code snippets for root cause and fix — these are the most valuable part
- Keep wikilinks relative (just the note name, not full path) for Obsidian compatibility

## Step 4: Present Draft for Review

Show the user:
1. The proposed file path
2. The full doc content
3. Which spine note will be updated

Ask: "Does this look right? Any changes before I save?"

## Step 5: Save and Update Spine

After user approval:

1. **Write the doc** to `{vault}/{repo}/{feature}/{filename}.md`
2. **Update the spine note** — add a `[[wikilink]]` to the new doc under the appropriate section (Fixes, Features, Architecture, Plans, Decisions)
3. **Check Claude memory** — if this is a new feature with no memory signpost, create one pointing to the spine note
4. **Confirm** — tell the user the doc is saved and where to find it in Obsidian

## Step 6: Detect Patterns (Optional)

After saving, quickly scan the feature's existing docs:
- Are there 3+ fixes touching the same area? Suggest an architecture doc
- Is there a fix that contradicts an earlier plan? Flag it
- Are any existing docs referencing files that have changed significantly? Flag as potentially stale

Report findings briefly — don't act without user approval.

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
