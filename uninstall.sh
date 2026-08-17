#!/bin/bash
# uninstall.sh - unregister the launchd agent and remove installed files.
# Settings in ~/.config/bluetooth-battery-alert are kept unless --purge is given.
set -euo pipefail

LABEL="com.bluetooth-battery-alert.check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Library/Application Support/bluetooth-battery-alert"
NOTIFIER_APP="$HOME/Applications/BluetoothBatteryAlert.app"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bluetooth-battery-alert"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$APP_DIR" "$NOTIFIER_APP"
rm -f "$HOME/Library/Logs/bluetooth-battery-alert.log" "$HOME/Library/Logs/bluetooth-battery-alert.err"

echo "Uninstalled."
if [ "$PURGE" -eq 1 ]; then
  rm -rf "$CONFIG_DIR"
  echo "Settings removed."
elif [ -d "$CONFIG_DIR" ]; then
  echo "Settings kept at $CONFIG_DIR (remove them with: ./uninstall.sh --purge)"
fi
