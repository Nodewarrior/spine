#!/bin/bash
# Spine Pulse — macOS notification runner (invoked by launchd, or manually)
# Runs the stale-WIP scan, then fires a native macOS notification when stale
# items exist. No LLM calls. Silent-fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"

VAULT_PATH=$(bash "$HOOKS_DIR/spine-resolve-vault.sh" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  exit 0
fi

bash "$HOOKS_DIR/spine-pulse-scan.sh" >/dev/null 2>&1 || true

PULSE_FILE="$VAULT_PATH/.spine/pulse.json"
[ -f "$PULSE_FILE" ] || exit 0
command -v python3 &>/dev/null || exit 0
command -v osascript &>/dev/null || exit 0

SUMMARY=$(python3 - "$PULSE_FILE" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        pulse = json.load(f)
except Exception:
    sys.exit(0)
items = pulse.get("items", [])
if not items:
    sys.exit(0)
parts = [f"{i['repo']} {i['days_idle']:.0f}d" for i in items[:3]]
more = f" +{len(items) - 3} more" if len(items) > 3 else ""
print(f"{len(items)} stale WIP: " + ", ".join(parts) + more)
PYEOF
)

[ -z "$SUMMARY" ] && exit 0

# osascript arguments are passed positionally — never interpolated into the
# AppleScript source — so repo/branch names cannot inject script.
osascript - "$SUMMARY" <<'OSA' >/dev/null 2>&1 || true
on run argv
  display notification (item 1 of argv) with title "Spine Pulse" subtitle "Forgotten work is waiting" sound name "Ping"
end run
OSA

exit 0
