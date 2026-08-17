#!/bin/bash
# check_bt_battery.sh — notify if a connected Bluetooth accessory (mouse,
# keyboard, etc.) battery is below THRESHOLD.
#
# Detection method: `ioreg -c AppleDeviceManagementHIDEventService -r -l`
# lists each connected HID device as a "Product" line immediately followed
# by its "BatteryPercent" line. Wired/internal devices (e.g. a laptop's
# built-in keyboard/trackpad) have no BatteryPercent line and are skipped
# automatically — no filtering needed.
#
# Run manually to test, or install via install.sh to run on a schedule.

set -euo pipefail

THRESHOLD=20  # percent — edit to change the alert level

LOW=$(ioreg -c AppleDeviceManagementHIDEventService -r -l | awk -F'= ' -v thresh="$THRESHOLD" '
  /"Product"/        { gsub(/"/,"",$2); dev=$2 }
  /"BatteryPercent"/ {
    pct=$2+0
    if (pct < thresh) print dev ": " pct "%"
  }
')

if [ -n "$LOW" ]; then
  msg=$(echo "$LOW" | paste -sd', ' -)
  osascript -e "display notification \"Charge: $msg\" with title \"Bluetooth Battery Low\" sound name \"Glass\""
fi
