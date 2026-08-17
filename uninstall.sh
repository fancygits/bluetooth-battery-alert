#!/bin/bash
# uninstall.sh - unregister and remove the launchd agent.
set -euo pipefail

LABEL="com.btbatteryalert.check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "Uninstalled."
