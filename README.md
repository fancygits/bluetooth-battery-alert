# bt-battery-alert

Native macOS notification when a Bluetooth mouse or keyboard battery runs
low, checked on a schedule (default: Monday-Thursday at 5pm, so you know to
charge it before leaving work - and skip Friday since it won't sit plugged
in over the weekend).

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
skipped automatically. Any device below the threshold triggers a native
notification via `osascript`. Device names are passed to `osascript` as
arguments (never spliced into the AppleScript source), so an oddly or
maliciously named device can't inject script.

`install.sh` copies the script to
`~/Library/Application Support/btbatteryalert/` and registers it as a
`launchd` LaunchAgent, building the plist with `PlistBuddy`. Everything is
per-user; no `sudo`, nothing outside your home directory.

## Requirements

- macOS (uses `ioreg`, `osascript`, `PlistBuddy`, all built in)
- Verified against real hardware output on macOS as of August 2026. `ioreg`
  is not a documented, version-guaranteed API - if Apple changes the
  `AppleDeviceManagementHIDEventService` internals in a future macOS
  release, this may need adjusting. The script logs a warning when it finds
  no battery-reporting devices at all, which is the usual symptom of a
  format change (see Troubleshooting).

## Install

```bash
git clone <this-repo-url>
cd bt-battery-alert
./install.sh
```

Options (all optional):

```
--threshold N   alert when battery is below N percent (1-99, default 20)
--hour H        hour of day to run, 0-23 (default 17)
--minute M      minute of the hour, 0-59 (default 0)
--days LIST     comma-separated days: 0-6 or sun,mon,tue,wed,thu,fri,sat
                (default mon,tue,wed,thu)
```

Example: `./install.sh --threshold 15 --hour 16 --minute 30 --days mon,wed,fri`

Safe to re-run any time (e.g. to change the schedule) - it reinstalls
cleanly and keeps your settings. The installer fires a test notification
at the end; if macOS asks to allow notifications, click **Allow**, or
scheduled alerts will be silently suppressed.

## Customize

Settings live in `~/.config/btbatteryalert/config` and are read fresh on
every run - edit and save, no reinstall needed:

```
THRESHOLD=20              # alert below this percent (1-99)
SOUND=Glass               # notification sound name
IGNORE=                   # comma-separated device names to skip
```

The **schedule** is the one thing that lives in launchd rather than the
config file: change it by re-running `./install.sh` with `--hour`,
`--minute`, and/or `--days`.

## Test it immediately

```bash
bash ~/Library/Application\ Support/btbatteryalert/check_bt_battery.sh
```

Nothing happens if all devices are above threshold. To force a
notification, temporarily set `THRESHOLD=99` in
`~/.config/btbatteryalert/config`, run it again, then set it back.

## Uninstall

```bash
./uninstall.sh          # removes the agent, script copy, and logs
./uninstall.sh --purge  # also removes your settings
```

## Development

```bash
./test.sh
```

Runs an offline test suite: `ioreg`, `osascript`, and `launchctl` are
stubbed on `PATH` and everything runs against fixture data in a throwaway
`HOME`, so it needs no Bluetooth hardware, sends no real notifications,
and never touches your actual launchd agents or settings. It also lints
all scripts with `bash -n` and `shellcheck` (install via
`brew install shellcheck`; skipped with a note if absent). The same suite
runs in GitHub Actions on every push (`.github/workflows/ci.yml`).

Note the tests pin today's `ioreg` output shape via fixtures - they catch
regressions in this project's own logic, not changes Apple makes to
`ioreg` in a future macOS release.

## Credits

This project was inspired by [Freddy Reyes' blog post on macOS Bluetooth
battery alerts](https://freddyreyes.com/blog/macos-bluetooth-battery-alert/).

## Troubleshooting

Logs from scheduled runs land in `~/Library/Logs/btbatteryalert.log` and
`~/Library/Logs/btbatteryalert.err`. A "no battery-reporting devices
found" warning in the `.err` log on every run (while a Bluetooth mouse or
keyboard is connected) means `ioreg` no longer reports devices in the
expected shape. Confirm with:

```bash
ioreg -c AppleDeviceManagementHIDEventService -r -l | grep -E 'Product|BatteryPercent'
```

You should see each device's `Product` line immediately followed by its
`BatteryPercent` line. If the format has changed, update the `awk` parsing
in `check_bt_battery.sh` to match, then re-run `./install.sh`.

If no notification ever appears even with a low threshold, check
System Settings > Notifications and make sure notifications are allowed
for Script Editor / osascript.
