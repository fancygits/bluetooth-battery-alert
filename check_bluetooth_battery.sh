#!/bin/bash
# check_bluetooth_battery.sh - notify if a connected Bluetooth accessory (mouse,
# keyboard, etc.) battery is below THRESHOLD.
#
# Detection method: `ioreg -c AppleDeviceManagementHIDEventService -r -l`
# lists each connected HID device as a "Product" line immediately followed
# by its "BatteryPercent" line. Wired/internal devices (e.g. a laptop's
# built-in keyboard/trackpad) have no BatteryPercent line and are skipped
# automatically - no filtering needed.
#
# Settings come from ~/.config/bluetooth-battery-alert/config (KEY=VALUE lines);
# the defaults below apply when the file or a key is missing. The config
# is parsed, so a config line can never execute code.
#
# Run manually to test, or install via install.sh to run on a schedule.

set -euo pipefail

THRESHOLD=20   # percent (1-99)
SOUND=Glass    # notification sound name
IGNORE=""      # comma-separated device names to skip

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/bluetooth-battery-alert/config"

warn() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

if [ -f "$CONFIG_FILE" ]; then
  while IFS='=' read -r key val; do
    case "$key" in
      THRESHOLD) THRESHOLD=$val ;;
      SOUND)     SOUND=$val ;;
      IGNORE)    IGNORE=$val ;;
    esac
  done < "$CONFIG_FILE"
fi

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 99 ]; then
  warn "invalid THRESHOLD '$THRESHOLD' in $CONFIG_FILE; using 20"
  THRESHOLD=20
fi

# First output line: count of battery-reporting devices seen (for the
# format-drift warning below). Remaining output: the low-battery message.
OUT=$(ioreg -c AppleDeviceManagementHIDEventService -r -l | awk -F'= ' -v thresh="$THRESHOLD" -v ignore="$IGNORE" '
  BEGIN { n = split(ignore, ign, /, */) }
  /"Product"/        { gsub(/"/,"",$2); dev=$2 }
  /"BatteryPercent"/ {
    seen++
    skip = 0
    for (i = 1; i <= n; i++) if (dev == ign[i]) skip = 1
    pct = $2+0
    if (!skip && pct < thresh) msg = msg (msg ? ", " : "") dev ": " pct "%"
  }
  END { print seen+0; print msg }
')

SEEN=${OUT%%$'\n'*}
LOW=""
[[ "$OUT" == *$'\n'* ]] && LOW=${OUT#*$'\n'}

if [ "$SEEN" -eq 0 ]; then
  warn "no battery-reporting devices found - either none are connected, or the ioreg output format has changed (see README troubleshooting)"
fi

if [ -n "$LOW" ]; then
  # Device names and the sound name are passed as arguments, never
  # interpolated into the AppleScript source - a device named
  # `x" & (do shell script ...)` stays inert text.
  osascript \
    -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title "Bluetooth Battery Low" sound name (item 2 of argv)' \
    -e 'end run' \
    -- "Charge: $LOW" "$SOUND"
fi
