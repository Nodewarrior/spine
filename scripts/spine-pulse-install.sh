#!/bin/bash
# Spine Pulse — install/uninstall the daily launchd notifier (macOS)
# Usage:
#   spine-pulse-install.sh            install (default 09:00 daily)
#   spine-pulse-install.sh 18 30      install at 18:30 daily
#   spine-pulse-install.sh --uninstall
#
# Writes ~/Library/LaunchAgents/com.spine.pulse.plist pointing at
# spine-pulse-notify.sh in this plugin checkout. Plist is generated with
# plistlib (safe for any path characters) and lint-checked before loading.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.spine.pulse.plist"
LABEL="com.spine.pulse"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "🦴 Spine Pulse: launchd notifier removed."
  exit 0
fi

HOUR="${1:-9}"
MINUTE="${2:-0}"
case "$HOUR" in (*[!0-9]*|"") echo "Invalid hour: $HOUR" >&2; exit 1;; esac
case "$MINUTE" in (*[!0-9]*|"") echo "Invalid minute: $MINUTE" >&2; exit 1;; esac
# Force decimal — zero-padded input like "09" would otherwise parse as octal
HOUR=$((10#$HOUR))
MINUTE=$((10#$MINUTE))
if [ "$HOUR" -gt 23 ] || [ "$MINUTE" -gt 59 ]; then
  echo "Invalid time: $HOUR:$MINUTE" >&2; exit 1
fi

NOTIFY="$SCRIPT_DIR/spine-pulse-notify.sh"
if [ ! -f "$NOTIFY" ]; then
  echo "spine-pulse-notify.sh not found next to this script" >&2; exit 1
fi
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"

python3 - "$PLIST" "$LABEL" "$NOTIFY" "$HOUR" "$MINUTE" <<'PYEOF'
import plistlib, sys
plist_path, label, notify, hour, minute = sys.argv[1:6]
data = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", notify],
    "StartCalendarInterval": {"Hour": int(hour), "Minute": int(minute)},
    "StandardOutPath": "/tmp/spine-pulse.log",
    "StandardErrorPath": "/tmp/spine-pulse.log",
}
with open(plist_path, "wb") as f:
    plistlib.dump(data, f)
PYEOF

plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf '🦴 Spine Pulse: daily notifier installed (%02d:%02d). Uninstall with --uninstall.\n' "$HOUR" "$MINUTE"
