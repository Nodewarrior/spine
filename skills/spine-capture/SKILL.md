---
name: spine-capture
description: Capture completed work (fix, feature, architecture decision, plan) as an Obsidian doc in the Spine Architecture vault. Auto-detects repo, feature, and doc type from context.
argument-hint: [optional: description of what to capture]
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
