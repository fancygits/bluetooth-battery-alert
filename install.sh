#!/bin/bash
# install.sh - install the Bluetooth battery check and register it as a
# launchd agent. Safe to re-run (reinstalls cleanly, keeps your config).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]
  --threshold N   alert when battery is below N percent (1-99, default 20)
  --hour H        hour of day to run, 0-23 (default 17)
  --minute M      minute of the hour, 0-59 (default 0)
  --days LIST     comma-separated days: 0-6 or sun,mon,tue,wed,thu,fri,sat
                  (default mon,tue,wed,thu)
  -h, --help      show this help

Examples:
  ./install.sh
  ./install.sh --threshold 15 --hour 16 --minute 30 --days mon,wed,fri
EOF
}

die() { echo "install.sh: $*" >&2; exit 1; }
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

[ "$(uname)" = "Darwin" ] || die "this tool is macOS-only (needs ioreg, osascript, launchd)"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.bluetooth-battery-alert.check"
APP_DIR="$HOME/Library/Application Support/bluetooth-battery-alert"
SCRIPT_DEST="$APP_DIR/check_bluetooth_battery.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bluetooth-battery-alert"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_DIR="$HOME/Library/Logs"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
PB=/usr/libexec/PlistBuddy

HOUR=17
MINUTE=0
DAYS_RAW="mon,tue,wed,thu"
THRESHOLD_FLAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD_FLAG="${2:-}"; shift 2 ;;
    --hour)      HOUR="${2:-}";           shift 2 ;;
    --minute)    MINUTE="${2:-}";         shift 2 ;;
    --days)      DAYS_RAW="${2:-}";       shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown option '$1'" ;;
  esac
done

is_int "$HOUR"   && [ "$HOUR"   -le 23 ] || die "--hour must be 0-23"
is_int "$MINUTE" && [ "$MINUTE" -le 59 ] || die "--minute must be 0-59"
if [ -n "$THRESHOLD_FLAG" ]; then
  is_int "$THRESHOLD_FLAG" && [ "$THRESHOLD_FLAG" -ge 1 ] && [ "$THRESHOLD_FLAG" -le 99 ] \
    || die "--threshold must be 1-99"
fi

day_num() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    0|sun*) echo 0 ;;
    1|mon*) echo 1 ;;
    2|tue*) echo 2 ;;
    3|wed*) echo 3 ;;
    4|thu*) echo 4 ;;
    5|fri*) echo 5 ;;
    6|sat*) echo 6 ;;
    *) return 1 ;;
  esac
}
day_name() {
  case "$1" in
    0) echo Sun ;; 1) echo Mon ;; 2) echo Tue ;; 3) echo Wed ;;
    4) echo Thu ;; 5) echo Fri ;; 6) echo Sat ;;
  esac
}

[ -n "$DAYS_RAW" ] || die "--days must list at least one day"
DAYS=()
IFS=',' read -ra day_parts <<< "$DAYS_RAW"
for p in "${day_parts[@]}"; do
  n=$(day_num "$p") || die "unrecognized day '$p' in --days (use 0-6 or sun,mon,tue,wed,thu,fri,sat)"
  DAYS+=("$n")
done
[ "${#DAYS[@]}" -gt 0 ] || die "--days must list at least one day"

# Install the script to a stable, user-owned location so the agent never
# executes files out of the (movable, possibly shared) repo clone.
mkdir -p "$APP_DIR" "$CONFIG_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
install -m 755 "$REPO_DIR/check_bluetooth_battery.sh" "$SCRIPT_DEST"

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
# bluetooth-battery-alert settings. One KEY=VALUE per line, no quotes, no trailing
# comments. Read fresh on every scheduled run - edits apply immediately,
# no reinstall needed.

# Alert when a device battery is below this percent (1-99).
THRESHOLD=20

# Notification sound (a name from System Settings > Sound > Alert Sounds).
SOUND=Glass

# Comma-separated device names to skip, e.g.: IGNORE=MX Master 3,AirPods Pro
IGNORE=
EOF
fi

if [ -n "$THRESHOLD_FLAG" ]; then
  if grep -q '^THRESHOLD=' "$CONFIG_FILE"; then
    sed -i '' "s/^THRESHOLD=.*/THRESHOLD=$THRESHOLD_FLAG/" "$CONFIG_FILE"
  else
    printf 'THRESHOLD=%s\n' "$THRESHOLD_FLAG" >> "$CONFIG_FILE"
  fi
fi

# Build the plist with PlistBuddy rather than text substitution, so paths
# containing sed/XML metacharacters (#, &, <, spaces) can't corrupt it.
rm -f "$PLIST_DEST"
"$PB" -c "Add :Label string $LABEL" "$PLIST_DEST" >/dev/null
"$PB" -c "Add :ProgramArguments array" "$PLIST_DEST"
"$PB" -c "Add :ProgramArguments:0 string /bin/bash" "$PLIST_DEST"
"$PB" -c "Add :ProgramArguments:1 string $SCRIPT_DEST" "$PLIST_DEST"
"$PB" -c "Add :StartCalendarInterval array" "$PLIST_DEST"
i=0
for d in "${DAYS[@]}"; do
  "$PB" -c "Add :StartCalendarInterval:$i dict" "$PLIST_DEST"
  "$PB" -c "Add :StartCalendarInterval:$i:Weekday integer $d" "$PLIST_DEST"
  "$PB" -c "Add :StartCalendarInterval:$i:Hour integer $HOUR" "$PLIST_DEST"
  "$PB" -c "Add :StartCalendarInterval:$i:Minute integer $MINUTE" "$PLIST_DEST"
  i=$((i + 1))
done
"$PB" -c "Add :StandardOutPath string $LOG_DIR/bluetooth-battery-alert.log" "$PLIST_DEST"
"$PB" -c "Add :StandardErrorPath string $LOG_DIR/bluetooth-battery-alert.err" "$PLIST_DEST"
plutil -lint "$PLIST_DEST" >/dev/null

launchctl bootout "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

EFFECTIVE_THRESHOLD=$(grep '^THRESHOLD=' "$CONFIG_FILE" | tail -n1 | cut -d= -f2)
DAY_NAMES=$(for d in "${DAYS[@]}"; do day_name "$d"; done | paste -sd, -)

echo "Installed."
echo "  Schedule:  $DAY_NAMES at $(printf '%02d:%02d' "$HOUR" "$MINUTE")"
echo "  Threshold: below ${EFFECTIVE_THRESHOLD}%"
echo "  Settings:  $CONFIG_FILE (edits apply on the next run, no reinstall)"
echo "  Script:    $SCRIPT_DEST"
echo "  Logs:      $LOG_DIR/bluetooth-battery-alert.log and .err"
echo
echo "Sending a test notification now. If macOS asks to allow notifications"
echo "(from Script Editor or osascript), click Allow - otherwise scheduled"
echo "alerts will be silently suppressed."
osascript \
  -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title "Bluetooth Battery Low" sound name "Glass"' \
  -e 'end run' \
  -- "Install test - notifications are working." \
  || echo "warning: test notification failed; check System Settings > Notifications" >&2
echo
echo "Run a real check any time with: bash \"$SCRIPT_DEST\""
