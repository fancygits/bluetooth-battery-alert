#!/bin/bash
# install.sh - register the Bluetooth battery check as a launchd agent.
# Safe to re-run (reinstalls cleanly if already installed).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$REPO_DIR/check_bt_battery.sh"
LABEL="com.btbatteryalert.check"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

chmod +x "$SCRIPT_PATH"

mkdir -p "$HOME/Library/LaunchAgents"
sed "s#__SCRIPT_PATH__#$SCRIPT_PATH#" "$REPO_DIR/com.btbatteryalert.plist.template" > "$PLIST_DEST"

launchctl bootout "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

echo "Installed: runs Mon-Thu at 5:00pm."
echo "Test now with: bash \"$SCRIPT_PATH\""
