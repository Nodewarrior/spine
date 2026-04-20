# Changelog

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
