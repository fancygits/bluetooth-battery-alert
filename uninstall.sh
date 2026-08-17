#!/bin/bash
# uninstall.sh - unregister the launchd agent and remove installed files.
# Settings in ~/.config/btbatteryalert are kept unless --purge is given.
set -euo pipefail

LABEL="com.btbatteryalert.check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Library/Application Support/btbatteryalert"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/btbatteryalert"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$APP_DIR"
rm -f "$HOME/Library/Logs/btbatteryalert.log" "$HOME/Library/Logs/btbatteryalert.err"

echo "Uninstalled."
if [ "$PURGE" -eq 1 ]; then
  rm -rf "$CONFIG_DIR"
  echo "Settings removed."
elif [ -d "$CONFIG_DIR" ]; then
  echo "Settings kept at $CONFIG_DIR (remove them with: ./uninstall.sh --purge)"
fi
