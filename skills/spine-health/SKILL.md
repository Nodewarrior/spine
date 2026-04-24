---
name: spine-health
description: Scan the Spine Architecture Obsidian vault for gaps, stale docs, duplicates, and missing coverage. On-demand curator for vault hygiene.
argument-hint: [optional: specific feature or repo to scan]
---

# Spine Health — Vault Curator Scan

Audit the Spine Architecture vault for quality and completeness.

## Vault Path Resolution

Resolve the vault path using this config chain:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → read the `vaultPath` field
3. Default: `~/Documents/SpineVault/`

If the vault doesn't exist, tell the user to run `/spine-init` first.

## Scope

If `$ARGUMENTS` specifies a feature or repo, limit the scan to that area. Otherwise, scan the entire vault.

## Check 1: Coverage Gaps

Compare recent git history against existing Obsidian docs to find undocumented work.

1. Run `git log --oneline --since="2 weeks ago"` in the current repo
2. Group commits by feature area (based on file paths changed)
3. For each group, check if a corresponding Obsidian doc exists
4. Report any significant work (not just typo fixes) that has no documentation

**Output:**
```
## Coverage Gaps
- [repo/feature] 3 commits touching auth logic — no doc since YYYY-MM-DD
- [repo/feature] New API endpoint added — no architecture doc
```

## Check 2: Stale Docs

Find docs that reference code that has changed significantly since the doc was written.

1. Read each doc's `**Files changed:**` section
2. For each referenced file, check `git log --oneline --since="{doc date}" -- {filepath}`
3. If the file has 3+ commits since the doc was written, flag as potentially stale

**Output:**
```
## Potentially Stale
- Fix - Session Bug (2026-03-18) — session.hook.ts has 5 commits since
```

## Check 3: Duplicate/Overlapping Docs

Find docs within the same feature that describe overlapping issues.

1. Read all docs under each feature folder
2. Check for:
   - Same files referenced in multiple docs
   - Similar root causes described
   - Wikilinks that create circular clusters
3. Suggest consolidation where appropriate

## Check 4: Spine Note Integrity

Verify each spine note accurately reflects its children.

1. List all files in each feature folder
2. Compare against wikilinks in the spine note
3. Flag:
   - Docs that exist but aren't linked from the spine
   - Wikilinks that point to non-existent docs (ghost links)
   - Missing sections (e.g., feature has fixes but spine has no "## Fixes" section)

## Check 5: Tag Consistency

Verify all docs have proper `type/*` tags for graph coloring.

1. Read frontmatter of every doc in the vault (skip `.obsidian/`)
2. Flag any doc missing a `type/*` tag
3. Flag any doc with a `type/*` tag that doesn't match its naming prefix

## Check 6: Claude Memory Sync

Verify Claude memory signposts match the vault structure.

1. Read `MEMORY.md` from the project memory directory
2. Compare feature signposts against feature folders in the vault
3. Flag:
   - Features in vault with no memory signpost
   - Memory signposts pointing to features that don't exist
   - Incorrect spine paths in memory signposts

## Summary Report

Present a summary table:

```
## Spine Health Report — {date}

| Check | Status | Issues |
|-------|--------|--------|
| Coverage | {pass/warn} | {count} gaps |
| Staleness | {pass/warn} | {count} stale docs |
| Duplicates | {pass/warn} | {count} candidates |
| Spine Integrity | {pass/warn} | {count} issues |
| Tags | {pass/warn} | {count} missing |
| Memory Sync | {pass/warn} | {count} mismatches |
```

Then list each issue with a suggested action. Do NOT auto-fix — present findings and let the user decide.

If user approves fixes, use `/spine-capture` for new docs, and direct edits for spine note / tag updates.

## Update Health Timestamp

After presenting the report, write the current ISO timestamp to `{vault}/.spine/last-health-timestamp`. This lets `/spine-scan` know when the last full health check was run and remind the user when it's been too long (14+ days).
