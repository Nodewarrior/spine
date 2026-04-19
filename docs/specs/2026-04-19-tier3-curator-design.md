# Tier 3 Curator — Design Spec

**Date:** 2026-04-19
**Status:** Approved
**Author:** Akshay Kumar Kataiah

## Overview

Tier 3 evolves Spine from a set of human-invoked tools into a self-maintaining system. The vault maintains itself, knowledge capture happens automatically, and the user stays in control of what matters.

### Scope

- **Decay detection and auto-repair** — broken wikilinks, missing tags, orphan docs, stale content
- **Coverage gap detection** — undocumented commits surfaced automatically
- **Batch capture at session end** — commits tracked silently, docs drafted and presented for approval

### Out of Scope (Future)

- Curation quality (doc rewrites, consolidation suggestions) — Tier 4
- `/spine-search` — full-text vault search
- Cross-vault discovery
- Cloud sync

## Architecture

### Approach

Two new skills + enhanced hook (Approach B from brainstorming):

- **`/spine-scan`** — session-start scanner for decay and integrity
- **`/spine-capture --batch`** — enhanced capture with batch mode for session-end
- **Enhanced post-commit hook** — silently tracks commits instead of nudging

### Components

```
spine/
├── skills/
│   ├── spine-scan/              ← NEW: session-start decay/integrity scanner
│   ├── spine-capture/           ← ENHANCED: adds --batch mode
│   ├── spine-health/            ← UNCHANGED
│   └── spine-init/              ← UNCHANGED
├── hooks/
│   ├── hooks.json               ← ENHANCED: adds SessionStart + Stop hooks
│   ├── spine-commit-tracker.sh  ← NEW: replaces spine-commit-check.sh
│   ├── spine-commit-check.sh    ← REMOVED: replaced by tracker
│   └── spine-resolve-vault.sh   ← UNCHANGED
└── templates/
    └── curator-log.md           ← NEW: template for audit log
```

### State Files (in vault)

| File | Purpose |
|---|---|
| `{vault}/.spine/pending-commits.json` | Commits tracked during session, consumed by batch capture |
| `{vault}/.spine/last-scan-timestamp` | ISO timestamp of last scan run |
| `{vault}/.spine/curator-log.md` | Append-only audit trail of all auto-actions |

## Autonomy Model

### Auto-fix (no approval needed)

| Action | Rationale |
|---|---|
| Fix broken wikilinks | Deterministic — link target exists or it doesn't |
| Correct missing/wrong type tags | Deterministic — doc name prefix maps to tag |
| Link orphan docs into spine notes | Deterministic — doc exists in feature folder but not linked |
| Flag stale docs in frontmatter | Objective — file has 3+ commits since doc date |
| Correct memory signposts | Deterministic — vault structure is the source of truth |

### Requires user approval

| Action | Rationale |
|---|---|
| Create new docs (coverage gaps) | Judgment call — what to document, how to describe |
| Rewrite stale docs | Creative work — needs human review |
| Consolidate duplicate docs | Judgment call — what to keep, what to merge |
| Create new feature folders / spine notes | Structural decision — naming, scope |
| Delete or archive docs | Destructive — irreversible |

### User overrides

- All existing manual workflows (`/spine-capture`, `/spine-health`) continue to work unchanged
- Hooks can be disabled in `hooks.json`
- Session-start banner is non-blocking — can be ignored
- Batch capture at session end presents choices — skip any or all
- Curator log provides full transparency for reverting auto-fixes

## `/spine-scan` — Session-Start Scanner

**Trigger:** Automatically via `SessionStart` hook. Also invocable manually.

### Flow

```
Session starts
  → Hook fires /spine-scan
  → Resolve vault path (config chain: $SPINE_VAULT_PATH → ~/.spine/config.json → default)
  → If no vault found, skip silently (not every repo uses Spine)

Phase 1: Auto-fixes (silent, logged to curator-log.md)
  → Scan all docs for broken wikilinks → fix them
  → Scan frontmatter for missing/wrong type tags → correct them
  → Find orphan docs (in feature folder but not linked from spine note) → add wikilink
  → Check files referenced in docs against git log → flag stale (3+ commits since doc date)
  → Append all actions to curator-log.md

Phase 2: Coverage gap detection
  → Read {vault}/.spine/last-scan-timestamp
  → Run git log --since={last-scan} to find commits since last scan
  → Also check {vault}/.spine/pending-commits.json for leftovers from abrupt session ends
  → Filter out trivial commits (style, lint, chore, docs, merge)
  → Group remaining by feature area (match file paths to existing features)
  → Check if corresponding docs exist
  → Collect gaps

Phase 3: Banner (non-blocking)
  → Print single summary line:
    🦴 Spine: 5 commits since last session — 2 wikilinks fixed, 1 tag corrected (auto).
       2 coverage gaps found (auth, payments). Run /spine-capture when ready.
  → Update {vault}/.spine/last-scan-timestamp
```

### Edge cases

- **No vault configured for this repo:** Skip silently, no error
- **Vault path exists but is empty:** Skip silently
- **No commits since last scan:** Banner shows "Vault is clean" or skips entirely
- **Pending commits from abrupt session end:** Included in coverage gap detection

## Post-Commit Tracker

**Replaces:** `spine-commit-check.sh` (the nudge hook)

### `spine-commit-tracker.sh`

```
After every git commit (via Claude Code PostToolUse hook):
  → Resolve vault path
  → If no vault or repo not tracked, exit silently
  → Apply significance filter:
    - Skip if < 20 total line changes AND <= 1 file changed
    - Skip merge commits
    - Skip style/lint/chore/docs commits
  → Append to {vault}/.spine/pending-commits.json:
    {
      "commits": [
        {
          "hash": "abc1234",
          "message": "fix: resolve cookie expiry on auth redirect",
          "files": ["src/auth/session.ts", "src/middleware/cookie.ts"],
          "insertions": 45,
          "deletions": 12,
          "timestamp": "2026-04-19T14:30:00Z",
          "repo": "web-app"
        }
      ]
    }
  → Silent. No output.
```

## `/spine-capture --batch` — Session-End Batch Capture

**Trigger:** Automatically via `Stop` hook. Also invocable manually.

### Flow

```
1. Read {vault}/.spine/pending-commits.json
   → If empty or missing, skip silently

2. Group commits by feature area
   → Match file paths to existing feature folders
   → Multiple commits touching the same feature = one doc, not multiple
   → Unrecognized paths = ask user to assign a feature (or create new)

3. For each group, draft an Obsidian doc
   → Read actual diffs to understand what changed
   → Classify: fix, feature, architecture, plan, decision
   → Apply naming conventions (date prefix for fix/feature, no date for others)
   → Apply frontmatter (title, date, tags, type, status)
   → Include code snippets for root cause and implementation

4. Present batch to user:
   "You had 3 significant commits this session:"

   [1] Fix - Cookie Expiry on Auth Redirect (Authentication)
       → 2 commits consolidated
       ✅ Save  ✏️ Edit  ❌ Skip

   [2] Feature - Rate Limiting Middleware (API)
       → 1 commit
       ✅ Save  ✏️ Edit  ❌ Skip

5. For approved docs:
   → Write to {vault}/{repo}/{feature}/{filename}.md
   → Update spine note with wikilink
   → Update Claude memory if new feature (add signpost)
   → Log to curator-log.md

6. Clear processed commits from pending-commits.json
   → Keep any that were skipped (user can capture later)
```

### Edge cases

- **Session ends abruptly (crash, Ctrl+C):** `pending-commits.json` persists. Next session's `/spine-scan` picks them up in Phase 2.
- **All commits skipped by user:** Cleared from pending. They can always manually `/spine-capture` later if they change their mind.
- **Commits from outside Claude Code:** Not tracked by the hook. Caught by `/spine-scan` Phase 2 via `git log --since`.
- **Manual `/spine-capture` still works:** Running without `--batch` does single interactive capture as today.

## Hooks Configuration

### Updated `hooks.json`

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash(git commit*)",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/spine-commit-tracker.sh\""
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "skill",
            "skill": "spine-scan"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "skill",
            "skill": "spine-capture",
            "args": "--batch"
          }
        ]
      }
    ]
  }
}
```

## Curator Log Format

`{vault}/.spine/curator-log.md` — append-only, newest entries at top.

```markdown
# Curator Log

## 2026-04-19 — Session Scan
- **Auto-fixed:** Broken wikilink in `Authentication.md` → `[[Fix - Cookie Expiry]]`
- **Auto-fixed:** Missing `type/fix` tag on `2026-04-18 Fix - Rate Limit Edge Case.md`
- **Auto-fixed:** Orphan doc `Architecture - OAuth Flow.md` linked into `Authentication.md`
- **Flagged stale:** `Fix - Session Bug.md` — `session.hook.ts` has 4 commits since doc date
- **Coverage gap:** 2 commits in `payments/` with no documentation

## 2026-04-19 — Batch Capture
- **Saved:** `2026-04-19 Fix - Cookie Expiry on Auth Redirect.md` (approved)
- **Saved:** `2026-04-19 Feature - Rate Limiting Middleware.md` (approved)
- **Skipped:** 1 commit in `utils/` (user declined)
```

## Migration from v0.1.0

- `spine-commit-check.sh` is replaced by `spine-commit-tracker.sh`
- `hooks.json` gains two new hook types (`SessionStart`, `Stop`)
- Existing vaults gain a `{vault}/.spine/` directory for state files on first run
- No changes to existing docs, spine notes, or vault structure
- `/spine-capture` without `--batch` continues to work as before
- `/spine-health` continues to work as before (manual deep audit)
