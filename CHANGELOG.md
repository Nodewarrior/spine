# Changelog

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
