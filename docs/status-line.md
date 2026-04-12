# Status Line Setup

Add a bone avatar to your Claude Code status line that shows vault activity.

## What It Shows

| State | Display | Color |
|-------|---------|-------|
| Vault quiet (no changes today) | `🦴 16` | Grey |
| Vault evolved (docs changed today) | `🦴 3↑/16` | Green |

The number after `↑` is how many docs were added or updated today. The total is all Spine docs in your vault.

## Setup

### Option 1: Standalone Status Line

If you don't have an existing status line, add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/spine/scripts/statusline-spine.sh"
  }
}
```

### Option 2: Add to Existing Status Line

If you already have a status line script, add this snippet at the end (before your final `printf`):

```bash
# Spine Architecture — vault activity
SPINE_VAULT=$(bash /path/to/spine/hooks/spine-resolve-vault.sh 2>/dev/null)
if [ -d "$SPINE_VAULT" ]; then
  green=$'\033[38;5;114m'
  grey=$'\033[38;5;244m'
  bold=$'\033[1m'
  reset=$'\033[0m'

  today=$(date +%Y-%m-%d)
  repo_dirs=$(find "$SPINE_VAULT" -mindepth 1 -maxdepth 1 -type d -not -name ".*" 2>/dev/null)
  recent=$(find $repo_dirs -name "*.md" -newermt "$today" 2>/dev/null | wc -l | tr -d '[:space:]')
  total=$(find $repo_dirs -name "*.md" 2>/dev/null | wc -l | tr -d '[:space:]')
  recent=${recent:-0}; total=${total:-0}

  if [ "$recent" -gt 0 ]; then
    spine_segment=" ${green}🦴 ${bold}${recent}↑${reset}${grey}/${total}${reset}"
  else
    spine_segment=" ${grey}🦴 ${total}${reset}"
  fi
fi
```

Then include `$spine_segment` in your final `printf`.
