# Changelog

## 0.4.0 (2026-06-03)

Memory Bridge — "Coexist" approach.

### New Skills
- `/spine-recall` — On-demand deep pull. Loads all vault docs for a feature area. Browse mode lists available features; targeted mode fuzzy-matches and loads everything.

### New Features
- **Auto-load at session start** — SessionStart hook now injects a compact vault index and retrieval policy into every session. Claude knows what spine docs exist from the first prompt. Controlled by `autoLoad` flag in `~/.spine/config.json` (default: `true`). Independent of Tier 3.
- **Retrieval policy** — shipped in `templates/retrieval-policy.md`. Teaches Claude three-hop vault navigation. Per-vault override supported at `{vault}/.spine/retrieval-policy.md`.

### Fixed
- SessionStart hook Bash 3.2 compatibility (macOS default shell)

## 0.3.0 (2026-05-28)

Resume and enrich existing docs.

### New Skills
- `/spine-update` — update an existing spine doc instead of creating a new one. Two modes:
  - **Targeted:** `/spine-update <name>` — fuzzy-matches a spine note, doc, or feature and appends an update.
  - **Auto-detect:** `/spine-update` (no args) — ranks stale docs (referenced files with new commits) and lets you pick which to update.
  - Append-only: preserves the original content and adds a dated update section drawn from git diffs plus session context. Best for plans and architecture docs that evolve across sessions.

## 0.2.0 (2026-04-19)

Tier 3: Self-Maintaining Vault.

### New Skills
- `/spine-scan` — session-start scanner with auto-fix for broken wikilinks, missing tags, orphan docs, and stale detection. Runs automatically at session start via hook.

### Enhanced Skills
- `/spine-capture --batch` — batch capture mode for session-end. Groups pending commits by feature, drafts docs, presents for approval.

### New Hooks
- `SessionStart` hook → triggers `/spine-scan` automatically
- `Stop` hook → triggers `/spine-capture --batch` at session end
- `spine-commit-tracker.sh` — silently tracks significant commits to `pending-commits.json` (replaces the nudge-style `spine-commit-check.sh`)

### New State Files
- `{vault}/.spine/pending-commits.json` — tracked commits awaiting batch capture
- `{vault}/.spine/last-scan-timestamp` — last scan time for gap detection
- `{vault}/.spine/curator-log.md` — append-only audit trail of all auto-actions

### Templates
- `curator-log.md` — template for the audit log

### Removed
- `spine-commit-check.sh` — replaced by `spine-commit-tracker.sh`

## 0.1.0 (2026-04-12)

Initial release.

### Skills
- `/spine-init` — vault setup wizard with fresh vault and adopt modes
- `/spine-capture` — auto-draft Obsidian docs from completed work
- `/spine-health` — vault audit with 6 checks (coverage, staleness, duplicates, integrity, tags, memory sync)

### Hooks
- Post-commit hook — nudges `/spine-capture` after significant commits (20+ lines, 2+ files)
- Vault path resolver — shared config chain (`$SPINE_VAULT_PATH` → `~/.spine/config.json` → default)

### Templates
- Spine Architecture meta doc
- Spine note template
- Obsidian graph color config (7 type-based color groups)

### Scripts
- Optional status line segment with bone avatar (`🦴`)

### Docs
- Naming conventions and tagging reference
- Status line setup guide
