---
name: spine-init
description: Initialize or adopt a Spine Architecture vault. Creates the Obsidian vault structure, graph color config, and config file. Run once per vault.
argument-hint: [vault-path]
---

# Spine Init — Vault Setup Wizard

Initialize a new Spine Architecture vault, or adopt an existing Obsidian vault into the Spine conventions.

## Vault Path Resolution

Spine uses a config chain to find the vault:
1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → `{ "vaultPath": "..." }`
3. Default: `~/Documents/SpineVault/`

## Step 1: Determine Mode

If `$ARGUMENTS` is provided, use it as the vault path. Otherwise, check the config chain for an existing path. If none found, ask the user.

Check if the path already contains an Obsidian vault (`.obsidian/` directory) or markdown files:
- **If yes** → Adopt mode
- **If no** → Fresh vault mode

## Step 2a: Fresh Vault Mode

1. Create the vault root directory at the chosen path
2. Ask the user: **"Enable Tier 3 autonomous mode?"**
   Explain briefly: "Tier 3 adds session-start scanning, silent commit tracking, and batch capture at session end. You can change this anytime in `~/.spine/config.json`."
   - If yes → `tier3: true`
   - If no (default) → `tier3: false`
3. Create `~/.spine/config.json`:
   ```json
   { "vaultPath": "/absolute/path/to/vault", "tier3": false }
   ```
3. Create `.obsidian/graph.json` with color groups:
   ```json
   {
     "collapse-filter": true,
     "search": "",
     "showTags": false,
     "showAttachments": false,
     "hideUnresolved": false,
     "showOrphans": true,
     "collapse-color-groups": false,
     "colorGroups": [
       { "query": "tag:#type/spine", "color": { "a": 1, "rgb": 3381759 } },
       { "query": "tag:#type/fix", "color": { "a": 1, "rgb": 14495282 } },
       { "query": "tag:#type/feature", "color": { "a": 1, "rgb": 4439473 } },
       { "query": "tag:#type/architecture", "color": { "a": 1, "rgb": 10170623 } },
       { "query": "tag:#type/plan", "color": { "a": 1, "rgb": 16750848 } },
       { "query": "tag:#type/decision", "color": { "a": 1, "rgb": 16776960 } },
       { "query": "tag:#type/meta", "color": { "a": 1, "rgb": 10066329 } }
     ],
     "collapse-display": true,
     "showArrow": false,
     "textFadeMultiplier": 0,
     "nodeSizeMultiplier": 1,
     "lineSizeMultiplier": 1,
     "collapse-forces": true,
     "centerStrength": 0.5,
     "repelStrength": 10,
     "linkStrength": 1,
     "linkDistance": 250,
     "scale": 1.6,
     "close": true
   }
   ```
4. Write `Spine Architecture.md` at the vault root:
   ```markdown
   ---
   tags:
     - type/meta
   ---

   # Spine Architecture

   A knowledge management system that bridges Claude Code's memory with this Obsidian vault, organizing project knowledge as a navigable graph tree.

   ## Structure

   ```
   {vault}/
     └─ {repo}/
          └─ {feature}/
               ├─ {Feature}.md           ← spine note (overview, wikilinks to all children)
               ├─ Fix - {description}.md
               ├─ Feature - {description}.md
               ├─ Architecture - {description}.md
               ├─ Plan - {description}.md
               └─ Decision - {description}.md
   ```

   ## Navigation

   Claude Memory → Feature Signpost → Spine Note → Specific Doc

   ## Conventions

   - **Repo-first** hierarchy separates concerns across codebases
   - **Feature-first** grouping within each repo keeps related knowledge together
   - **Spine notes** are the entry point — read the spine to understand a feature before diving in
   - **Naming convention** (`Fix -`, `Feature -`, `Architecture -`, `Plan -`, `Decision -`) keeps the tree shallow
   - **Type tags** (`type/spine`, `type/fix`, `type/feature`, `type/architecture`, `type/plan`, `type/decision`) drive graph coloring
   - **Cross-repo features** link to each other via `[[wikilinks]]`
   ```
5. Detect the current repo name from `basename $(git remote get-url origin 2>/dev/null) .git` or the current directory name
6. Create the first repo folder: `{vault}/{repo}/`
7. Ask the user: "What's the first feature you'd like to track?"
8. Create the feature folder and spine note using the template:
   ```markdown
   ---
   title: {Feature} — {repo}
   tags:
     - {repo}
     - {feature-kebab-case}
     - type/spine
   ---

   # {Feature} ({repo})

   {Brief description — ask user or derive from context}

   ## Fixes

   ## Features

   ## Architecture

   ## Plans

   ## Decisions
   ```

## Step 2b: Adopt Mode

1. Create `~/.spine/config.json` pointing to the existing vault
2. Scan the vault structure:
   - Find all repo folders (directories containing feature subdirectories)
   - Find all spine notes (files matching `{Feature}.md` at the feature folder level)
   - Find all doc files and classify by naming prefix
3. Check for `.obsidian/graph.json` — if missing or missing color groups, create/patch it
4. Validate conventions:
   - Flag docs missing `type/*` frontmatter tags
   - Flag spine notes with missing wikilinks to existing docs
   - Flag docs not linked from any spine note
5. Report findings:
   ```
   Adopted existing vault at {path}
   Found: {n} repos, {n} features, {n} docs
   - {n} docs with correct type tags
   - {n} docs missing type tags (run /spine-health to fix)
   - Graph colors: {configured/added}
   ```
6. Do NOT move, rename, or delete anything — adopt is read-only + additive

## Step 3: Next Steps

Print:
```
Spine vault ready at {path}

Next steps:
1. Open {path} in Obsidian (File → Open Vault → choose folder)
2. Press Cmd+G to see the color-coded knowledge graph
3. Use /spine-capture after completing work to add docs
4. Use /spine-health periodically to audit vault health
5. (Optional) Add the status line segment — see docs/status-line.md
```
