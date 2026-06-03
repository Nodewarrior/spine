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
