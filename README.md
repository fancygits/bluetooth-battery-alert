# bt-battery-alert

Native macOS notification when a Bluetooth mouse or keyboard battery runs
low, checked on a schedule (default: weekdays Monday–Thursday at 5pm, so
you know to charge it before leaving work — and skip Friday since it won't
sit plugged in over the weekend).

Runs entirely locally via `launchd`. No app, no background daemon, no
third-party dependency.

## How it works

`check_bt_battery.sh` runs:

```
ioreg -c AppleDeviceManagementHIDEventService -r -l
```

Each connected Bluetooth HID device (mouse, keyboard, trackpad, etc.)
appears as a `"Product"` line immediately followed by its
`"BatteryPercent"` line. Wired or built-in devices (e.g. a laptop's
internal keyboard/trackpad) have no `BatteryPercent` line, so they're
skipped automatically. Any device below `THRESHOLD` (default 20%) triggers
a native notification via `osascript`.

`install.sh` registers this script as a `launchd` LaunchAgent using
`com.btbatteryalert.plist.template`, which schedules it for Mon–Thu at
5:00pm via `StartCalendarInterval`.

## Requirements

- macOS (uses `ioreg` and `osascript`, both built in)
- Verified against real hardware output on macOS as of August 2026. `ioreg`
  is not a documented, version-guaranteed API — if Apple changes the
  `AppleDeviceManagementHIDEventService` internals in a future macOS
  release, this may need adjusting. Re-run the check below to confirm it
  still works after a major macOS upgrade.

## Install

```bash
git clone <this-repo-url>
cd bt-battery-alert
./install.sh
```

This is safe to re-run any time (e.g. after moving the repo folder) — it
reinstalls cleanly.

## Test it immediately

```bash
bash check_bt_battery.sh
```

Nothing happens if all devices are above threshold. To force a
notification, temporarily set `THRESHOLD=100` at the top of
`check_bt_battery.sh`, run it again, then set it back.

## Customize

- **Battery threshold**: edit `THRESHOLD` in `check_bt_battery.sh`, then
  re-run `./install.sh` (or just save — the script is read fresh each run,
  no reinstall needed for this change alone).
- **Schedule / days**: edit the `StartCalendarInterval` array in
  `com.btbatteryalert.plist.template` (`Weekday`: 0=Sun … 6=Sat), then
  re-run `./install.sh` to apply.

## Uninstall

```bash
./uninstall.sh
```

## Troubleshooting

If `check_bt_battery.sh` never fires, confirm `ioreg` still reports your
devices in the expected shape:

```bash
ioreg -c AppleDeviceManagementHIDEventService -r -l | grep -E 'Product|BatteryPercent'
```

You should see each device's `Product` line immediately followed by its
`BatteryPercent` line. If the format has changed, update the `awk` parsing
in `check_bt_battery.sh` to match.

Logs from scheduled runs land in `/tmp/btbatteryalert.log` and
`/tmp/btbatteryalert.err`.
