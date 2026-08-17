#!/bin/bash
# test.sh - offline test suite. Stubs ioreg/osascript/launchctl on PATH and
# runs the scripts against fixture data in a throwaway HOME, so it needs no
# Bluetooth hardware, sends no real notifications, and never touches your
# actual launchd agents or settings. Safe to run anywhere, including CI.
#
# Usage: ./test.sh    (exits nonzero if any check fails)
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
CURRENT_TEST=lint

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT
STUBS="$TMPROOT/bin"
FIXTURES="$TMPROOT/fixtures"
mkdir -p "$STUBS" "$FIXTURES"
export PATH="$STUBS:$PATH"

assert() {
  local desc=$1; shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $CURRENT_TEST: $desc"
  fi
}
not_grep() { ! grep -q "$1" "$2" 2>/dev/null; }
file_absent() { [ ! -e "$1" ]; }
quiet() { "$@" >/dev/null 2>&1; }

# ---- stubs -----------------------------------------------------------------
# ioreg replays a fixture; osascript records each argument on its own line;
# launchctl records each invocation. All read/write paths via env vars.
cat > "$STUBS/ioreg" <<'EOF'
#!/bin/bash
cat "$BTBA_FIXTURE"
EOF
cat > "$STUBS/osascript" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$OSA_LOG"
EOF
cat > "$STUBS/launchctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$LC_LOG"
EOF
chmod +x "$STUBS"/*

# ---- fixtures (shape of real `ioreg -c AppleDeviceManagementHIDEventService`)
cat > "$FIXTURES/low.txt" <<'EOF'
    "Product" = "MX Master 3"
    "BatteryPercent" = 5
    "Product" = "Magic Keyboard"
    "BatteryPercent" = 87
    "Product" = "Old Trackpad"
    "BatteryPercent" = 3
EOF
cat > "$FIXTURES/healthy.txt" <<'EOF'
    "Product" = "MX Master 3"
    "BatteryPercent" = 87
    "Product" = "Magic Keyboard"
    "BatteryPercent" = 64
EOF
# A device name that attempts AppleScript injection via the notification.
cat > "$FIXTURES/malicious.txt" <<EOF
    "Product" = "x" & (do shell script "touch $TMPROOT/pwned") & "
    "BatteryPercent" = 8
EOF
: > "$FIXTURES/empty.txt"

setup() {
  rm -rf "${TMPROOT:?}/home"
  mkdir -p "$TMPROOT/home"
  export HOME="$TMPROOT/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$XDG_CONFIG_HOME/btbatteryalert"
  CONFIG="$XDG_CONFIG_HOME/btbatteryalert/config"
  PLIST="$HOME/Library/LaunchAgents/com.btbatteryalert.check.plist"
  export OSA_LOG="$TMPROOT/osascript.log"
  export LC_LOG="$TMPROOT/launchctl.log"
  export BTBA_FIXTURE="$FIXTURES/healthy.txt"
  ERR="$TMPROOT/stderr"
  rm -f "$OSA_LOG" "$LC_LOG" "$ERR" "$TMPROOT/pwned"
}

# ---- check_bt_battery.sh ----------------------------------------------------

test_notifies_and_joins_multiple_devices() {
  export BTBA_FIXTURE="$FIXTURES/low.txt"
  local rc=0
  bash "$REPO/check_bt_battery.sh" 2>"$ERR" || rc=$?
  assert "exits 0" [ "$rc" -eq 0 ]
  assert "low devices joined with commas" \
    grep -qFx 'Charge: MX Master 3: 5%, Old Trackpad: 3%' "$OSA_LOG"
  assert "healthy device not included" not_grep 'Magic Keyboard' "$OSA_LOG"
  assert "no warnings" [ ! -s "$ERR" ]
}

test_no_notification_when_all_healthy() {
  export BTBA_FIXTURE="$FIXTURES/healthy.txt"
  local rc=0
  bash "$REPO/check_bt_battery.sh" 2>"$ERR" || rc=$?
  assert "exits 0" [ "$rc" -eq 0 ]
  assert "no notification sent" file_absent "$OSA_LOG"
  assert "no warnings" [ ! -s "$ERR" ]
}

test_malicious_device_name_stays_inert() {
  export BTBA_FIXTURE="$FIXTURES/malicious.txt"
  bash "$REPO/check_bt_battery.sh" 2>/dev/null
  assert "injection did not execute in our shell" file_absent "$TMPROOT/pwned"
  # The AppleScript source lines must stay fixed; the name may only appear
  # in the message argument (the line starting "Charge: ").
  local leaked
  leaked=$(grep -F 'do shell script' "$OSA_LOG" | grep -cv '^Charge: ') || true
  assert "malicious text only appears as message data" [ "$leaked" -eq 0 ]
  assert "script source has no interpolation" grep -qFx \
    'display notification (item 1 of argv) with title "Bluetooth Battery Low" sound name (item 2 of argv)' \
    "$OSA_LOG"
}

test_ignore_list_skips_device() {
  printf 'IGNORE=Old Trackpad\n' > "$CONFIG"
  export BTBA_FIXTURE="$FIXTURES/low.txt"
  bash "$REPO/check_bt_battery.sh" 2>/dev/null
  assert "ignored device excluded" not_grep 'Old Trackpad' "$OSA_LOG"
  assert "other low device still alerts" grep -q 'MX Master 3: 5%' "$OSA_LOG"
}

test_custom_sound_from_config() {
  printf 'SOUND=Ping\n' > "$CONFIG"
  export BTBA_FIXTURE="$FIXTURES/low.txt"
  bash "$REPO/check_bt_battery.sh" 2>/dev/null
  assert "custom sound passed as argument" grep -qFx 'Ping' "$OSA_LOG"
}

test_invalid_threshold_falls_back_to_default() {
  printf 'THRESHOLD=banana\n' > "$CONFIG"
  export BTBA_FIXTURE="$FIXTURES/low.txt"
  local rc=0
  bash "$REPO/check_bt_battery.sh" 2>"$ERR" || rc=$?
  assert "exits 0" [ "$rc" -eq 0 ]
  assert "warns about the bad value" grep -q "invalid THRESHOLD 'banana'" "$ERR"
  assert "still alerts using default 20" grep -q 'MX Master 3: 5%' "$OSA_LOG"
}

test_threshold_from_config_respected() {
  printf 'THRESHOLD=4\n' > "$CONFIG"
  export BTBA_FIXTURE="$FIXTURES/low.txt"
  bash "$REPO/check_bt_battery.sh" 2>/dev/null
  assert "3% device alerts at threshold 4" grep -q 'Old Trackpad: 3%' "$OSA_LOG"
  assert "5% device does not alert at threshold 4" not_grep 'MX Master 3' "$OSA_LOG"
}

test_warns_when_no_devices_seen() {
  export BTBA_FIXTURE="$FIXTURES/empty.txt"
  local rc=0
  bash "$REPO/check_bt_battery.sh" 2>"$ERR" || rc=$?
  assert "exits 0" [ "$rc" -eq 0 ]
  assert "warns about possible format drift" \
    grep -q 'no battery-reporting devices found' "$ERR"
  assert "no notification sent" file_absent "$OSA_LOG"
}

# ---- install.sh -------------------------------------------------------------

test_install_generates_valid_plist() {
  local rc=0
  (cd "$REPO" && ./install.sh --threshold 15 --hour 16 --minute 30 --days mon,wed,fri) \
    >/dev/null 2>&1 || rc=$?
  assert "install exits 0" [ "$rc" -eq 0 ]
  assert "plist lints" quiet plutil -lint "$PLIST"
  plutil -p "$PLIST" > "$TMPROOT/plist.txt"
  assert "runs Monday"    grep -q '"Weekday" => 1' "$TMPROOT/plist.txt"
  assert "runs Wednesday" grep -q '"Weekday" => 3' "$TMPROOT/plist.txt"
  assert "runs Friday"    grep -q '"Weekday" => 5' "$TMPROOT/plist.txt"
  assert "at hour 16"     grep -q '"Hour" => 16'   "$TMPROOT/plist.txt"
  assert "at minute 30"   grep -q '"Minute" => 30' "$TMPROOT/plist.txt"
  assert "logs under ~/Library/Logs" grep -q 'Library/Logs/btbatteryalert' "$TMPROOT/plist.txt"
  assert "script installed and executable" \
    [ -x "$HOME/Library/Application Support/btbatteryalert/check_bt_battery.sh" ]
  assert "threshold written to config" grep -qx 'THRESHOLD=15' "$CONFIG"
  assert "agent bootstrapped" grep -q 'bootstrap gui/' "$LC_LOG"
  assert "test notification fired" grep -q 'notifications are working' "$OSA_LOG"
}

test_install_rejects_bad_flags() {
  local badargs rc
  for badargs in '--hour 25' '--minute 60' '--threshold 0' '--threshold 100' \
                 '--threshold abc' '--days mon,funday' '--bogus'; do
    rc=0
    # shellcheck disable=SC2086  # word splitting of $badargs is intentional
    (cd "$REPO" && ./install.sh $badargs) >/dev/null 2>&1 || rc=$?
    assert "rejects: $badargs" [ "$rc" -ne 0 ]
    assert "no agent registered for: $badargs" not_grep 'bootstrap' "$LC_LOG"
  done
}

test_reinstall_keeps_config() {
  (cd "$REPO" && ./install.sh --threshold 15) >/dev/null 2>&1
  printf 'SOUND=Funk\n' >> "$CONFIG"
  (cd "$REPO" && ./install.sh) >/dev/null 2>&1
  assert "custom setting survives reinstall" grep -qx 'SOUND=Funk' "$CONFIG"
  assert "threshold survives reinstall" grep -qx 'THRESHOLD=15' "$CONFIG"
}

# ---- uninstall.sh -----------------------------------------------------------

test_uninstall_keeps_config_by_default() {
  (cd "$REPO" && ./install.sh) >/dev/null 2>&1
  (cd "$REPO" && ./uninstall.sh) >/dev/null 2>&1
  assert "plist removed" file_absent "$PLIST"
  assert "installed script removed" \
    file_absent "$HOME/Library/Application Support/btbatteryalert"
  assert "agent booted out" grep -q 'bootout gui/' "$LC_LOG"
  assert "config kept" [ -f "$CONFIG" ]
}

test_uninstall_purge_removes_config() {
  (cd "$REPO" && ./install.sh) >/dev/null 2>&1
  (cd "$REPO" && ./uninstall.sh --purge) >/dev/null 2>&1
  assert "config removed" file_absent "$XDG_CONFIG_HOME/btbatteryalert"
}

# ---- run --------------------------------------------------------------------

echo "== lint =="
for f in check_bt_battery.sh install.sh uninstall.sh test.sh; do
  assert "bash -n $f" bash -n "$REPO/$f"
done
if command -v shellcheck >/dev/null 2>&1; then
  assert "shellcheck" shellcheck "$REPO/check_bt_battery.sh" "$REPO/install.sh" \
    "$REPO/uninstall.sh" "$REPO/test.sh"
else
  echo "shellcheck not installed - skipping (brew install shellcheck)"
fi

echo "== tests =="
while read -r t; do
  CURRENT_TEST=$t
  setup
  "$t"
done < <(compgen -A function | grep '^test_')

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
