# Spine

**A self-developing knowledge management system for Claude Code.**

Spine bridges Claude Code's memory to an Obsidian vault, giving your AI agent persistent, structured knowledge that compounds with every commit. Your AI gets smarter with every fix, every feature, every decision.

> I started building Spine in March 2026 while working on production React/Express apps. The pain was simple: Claude kept rediscovering the same context from scratch every session. Fixes I'd spent hours debugging would be forgotten. Architecture decisions had no home. The knowledge died in the context window.
>
> Spine was my answer: a two-layer system where Claude memory becomes structured signposts pointing into an Obsidian vault of curated, feature-organized docs. It worked so well I open-sourced it.

## Why Spine?

Most AI memory solutions fall into two camps:

1. **Flat memory** — Claude Code's native memories. Lightweight but unstructured. No organization, no connections, no depth.
2. **Heavy infrastructure** — Knowledge graphs, vector DBs, MCP servers, Python dependencies. Powerful but complex to set up and maintain.

Spine sits in between. It's **just markdown files** in an Obsidian vault with a set of conventions that make them navigable by both humans and AI. No dependencies. No servers. No Python. Just files, wikilinks, and frontmatter tags.

```
Your vault/
  └─ your-repo/
       └─ Authentication/
            ├─ Authentication.md              ← spine note (the hub)
            ├─ 2026-03-18 Fix - Cookie Expiry.md
            ├─ Architecture - OAuth Flow.md
            └─ Decision - JWT vs Session.md
```

## How It Works

**Two layers, three hops:**

```
Claude Memory          →  Spine Note           →  Specific Doc
(one-line signpost)       (feature hub)           (root cause, code snippets)
```

1. **Claude Memory** — lightweight signposts. One entry per feature, pointing to a spine note. Loaded automatically every session.
2. **Obsidian Vault** — the full knowledge base. Spine notes link to fixes, features, architecture docs, plans, and decisions via `[[wikilinks]]`.

When Claude needs context on a feature, it reads the signpost (instant), then the spine note (feature overview), then the specific doc it needs. Three hops, each narrowing the scope. No vector search, no embeddings — just structured navigation.

## What Makes It Self-Developing

Spine doesn't just store knowledge — it grows itself:

- **`/spine-capture`** — After you complete work, this skill auto-drafts an Obsidian doc from your commits. Detects the repo, matches the feature, applies the naming conventions, updates the spine note with wikilinks. You review and approve.
- **`/spine-health`** — On-demand vault audit. Finds undocumented commits, stale docs, duplicate notes, broken wikilinks, missing tags, and memory sync issues.
- **Post-commit hook** — After significant commits (20+ lines, 2+ files), nudges you to run `/spine-capture`.
- **Status line** — Optional bone avatar (`🦴`) showing vault activity in your Claude Code status bar.

The vault gets richer with every commit. The richer it gets, the better Claude performs on your codebase. Compound interest for engineering knowledge.

## Install

```bash
claude plugin marketplace add Nodewarrior/spine
claude plugin install spine
```

Then inside Claude Code:

```
/spine-init ~/Documents/MyVault
```

This creates your vault, sets up the Obsidian graph colors, and scaffolds the first repo and feature.

**Already have an Obsidian vault?** `/spine-init` detects existing vaults and runs in adopt mode — it adds the config and graph colors without touching your files.

## Quick Start

```bash
# 1. Install the plugin
claude plugin marketplace add Nodewarrior/spine
claude plugin install spine

# 2. Initialize your vault
# In Claude Code:
/spine-init ~/Documents/MyVault

# 3. Open the vault in Obsidian
# File → Open Vault → choose your vault folder
# Press Cmd+G to see the color-coded graph

# 4. Start working. After a fix or feature:
/spine-capture

# 5. Periodically audit your vault:
/spine-health
```

## Graph Colors

Spine tags every doc with a `type/*` frontmatter tag. Obsidian's graph view renders them as color-coded nodes:

| Color | Tag | What it is |
|-------|-----|-----------|
| Blue | `type/spine` | Spine notes (feature hubs) |
| Red | `type/fix` | Bug fixes |
| Green | `type/feature` | New features |
| Purple | `type/architecture` | Architecture docs |
| Orange | `type/plan` | Implementation plans |
| Yellow | `type/decision` | Decision records |
| Grey | `type/meta` | Spine Architecture meta doc |

The color config is set up automatically by `/spine-init`.

## Naming Conventions

| Prefix | Example | Date prefix? |
|--------|---------|-------------|
| `Fix - ` | `2026-03-18 Fix - Auth Cookie Expiry.md` | Yes |
| `Feature - ` | `2026-03-19 Feature - No-Session Flow.md` | Yes |
| `Architecture - ` | `Architecture - API Routes.md` | No |
| `Plan - ` | `Plan - Migration Strategy.md` | No |
| `Decision - ` | `Decision - JWT vs Session.md` | No |

## Configuration

Spine resolves the vault path from:

1. `$SPINE_VAULT_PATH` environment variable
2. `~/.spine/config.json` → `{ "vaultPath": "/absolute/path" }`
3. Default: `~/Documents/SpineVault/`

## Repo Structure

```
spine/
├── .claude-plugin/          # Plugin metadata
├── skills/
│   ├── spine-init/          # Vault setup wizard
│   ├── spine-capture/       # Auto-draft docs from commits
│   └── spine-health/        # Vault audit and curation
├── hooks/
│   ├── hooks.json           # Post-commit hook config
│   ├── spine-commit-check.sh
│   └── spine-resolve-vault.sh
├── templates/               # Vault templates (used by spine-init)
├── scripts/
│   └── statusline-spine.sh  # Optional status line segment
└── docs/
    ├── conventions.md       # Full naming and tagging reference
    └── status-line.md       # Status line setup guide
```

## Philosophy

> *"The tedious part of maintaining a knowledge base is not the reading or the thinking — it's the bookkeeping."*

Spine automates the bookkeeping. You make decisions, fix bugs, build features. Spine writes the docs, updates the wikilinks, maintains the tags, and keeps the graph connected. The vault stays maintained because the cost of maintenance is near zero.

This is **compound interest for engineering knowledge**. Every doc makes the next session faster. Every wikilink makes discovery easier. Every spine note means Claude starts with context instead of starting from scratch.

The human's job: curate sources, direct the analysis, ask good questions, think about what it all means.

The AI's job: everything else.

## Prior Art and Inspiration

- **Vannevar Bush's Memex (1945)** — the original vision of a personal knowledge store with associative trails. Spine is closer to this than to what the web became.
- **Andrej Karpathy's autoResearch** — the iterative deepening loop that inspires Spine's planned Tier 3 autonomous curator.
- **LLM Wiki pattern** — a similar concept of LLM-maintained persistent wikis. Spine predates it with a more opinionated, feature-first structure.
- **Knowledge graph systems** — heavier infrastructure approaches (KG, PageRank, MCP servers) that complement Spine. Spine excels at curated feature docs; KG systems excel at cross-repo traversal and discovery.

## Roadmap

- [x] `/spine-init` — vault setup with fresh and adopt modes
- [x] `/spine-capture` — auto-draft docs from commits
- [x] `/spine-health` — vault audit (6 checks)
- [x] Post-commit hook — nudge after significant commits
- [x] Graph colors — type tags with Obsidian color groups
- [x] Status line — bone avatar with vault activity
- [ ] Tier 3 curator agent — autonomous vault maintenance (autoResearch-inspired)
- [ ] `/spine-search` — full-text search across the vault
- [ ] Cross-vault discovery — find related concepts across multiple vaults
- [ ] Cloud sync — integration for cross-machine persistence

## License

MIT
