# bluetooth-battery-alert

Native macOS notification when a Bluetooth mouse or keyboard battery runs
low, checked on a schedule (default: Monday-Thursday at 5pm, so you know to
charge it before leaving work - and skip Friday since it won't sit plugged
in over the weekend).

Runs entirely locally via `launchd`. No background daemon, no third-party
dependency - the one small `.app` involved is a notifier compiled from
source on your own Mac during install (see below), not a downloaded binary.

## How it works

`check_bluetooth_battery.sh` runs:

```
ioreg -c AppleDeviceManagementHIDEventService -r -l
```

Each connected Bluetooth HID device (mouse, keyboard, trackpad, etc.)
appears as a `"Product"` line immediately followed by its
`"BatteryPercent"` line. Wired or built-in devices (e.g. a laptop's
internal keyboard/trackpad) have no `BatteryPercent` line, so they're
skipped automatically. Any device below the threshold triggers a
notification via a small notifier app (see below). Device names reach it
as plain arguments, never as script or shell source, so an oddly or
maliciously named device can't inject anything.

`install.sh` copies the script to
`~/Library/Application Support/bluetooth-battery-alert/` and registers it as a
`launchd` LaunchAgent, building the plist with `PlistBuddy`. Everything is
per-user; no `sudo`, nothing outside your home directory.

### The notifier app

Notifications go through `BluetoothBatteryAlert.app`, a small Swift program
(`notifier/main.swift`) that `install.sh` compiles and ad-hoc signs on your
own machine every time you install. This is what gives alerts this
project's own name and icon (a plain `🔋`, generated at install time -
`notifier/make_icon.swift`) instead of a generic script icon, and makes
clicking one do nothing instead of opening Script Editor, which is what you
get from the more common `osascript -e 'display notification'` approach.

Building it locally instead of shipping a prebuilt binary matters for two
reasons: nothing is downloaded pre-compiled, so there's no Gatekeeper
"can't verify this app" prompt to work around, and no Homebrew or other
third-party dependency is needed - just Apple's own Swift compiler, which
you already have if you were able to `git clone` this repo (git itself
requires the Xcode Command Line Tools on a stock Mac).

The first time it ever runs, macOS will ask you to allow notifications for
"Bluetooth Battery Alert" - click **Allow**, or every alert after that will
be silently suppressed. This uses your own local build, signed with an
ad-hoc signature (no paid Apple Developer account or notarization needed).

## Requirements

- macOS on Apple Silicon or Intel (uses `ioreg`, `launchd`, `PlistBuddy`,
  `sips`, `iconutil`, all built in)
- Xcode Command Line Tools, to compile the notifier (`xcode-select
  --install` if `swiftc` isn't already on your `PATH` - `install.sh` checks
  and tells you if it's missing)
- Verified against real hardware output on macOS as of August 2026. `ioreg`
  is not a documented, version-guaranteed API - if Apple changes the
  `AppleDeviceManagementHIDEventService` internals in a future macOS
  release, this may need adjusting. The script logs a warning when it finds
  no battery-reporting devices at all, which is the usual symptom of a
  format change (see Troubleshooting).

## Install

### Via Homebrew

```bash
brew tap fancygits/bluetooth-battery-alert https://github.com/fancygits/bluetooth-battery-alert
brew install bluetooth-battery-alert
bluetooth-battery-alert install
```

`brew install` only stages the `bluetooth-battery-alert` command; it
doesn't touch launchd or fire the permission prompt on its own (installing
a background scheduled job and popping a system dialog isn't something a
package install should do silently). Run `bluetooth-battery-alert install`
right after to actually build the notifier and register the schedule -
see Customize below for the same `--threshold`/`--hour`/`--minute`/`--days`
flags. To update later: `brew upgrade bluetooth-battery-alert` (pulls the
latest `main`), then re-run `bluetooth-battery-alert install` to rebuild.

To remove it, run these in order - `brew uninstall` alone only removes the
command itself, not the LaunchAgent it registered:

```bash
bluetooth-battery-alert uninstall
brew uninstall bluetooth-battery-alert
```

### From source

```bash
git clone https://github.com/fancygits/bluetooth-battery-alert
cd bluetooth-battery-alert
./install.sh
```

Options (all optional, same ones `bluetooth-battery-alert install` above takes):

```
--threshold N   alert when battery is below N percent (1-99, default 20)
--hour H        hour of day to run, 0-23 (default 17)
--minute M      minute of the hour, 0-59 (default 0)
--days LIST     comma-separated days: 0-6 or sun,mon,tue,wed,thu,fri,sat
                (default mon,tue,wed,thu)
```

Example: `./install.sh --threshold 15 --hour 16 --minute 30 --days mon,wed,fri`

Safe to re-run any time (e.g. to change the schedule) - it reinstalls
cleanly, keeps your settings, and rebuilds the notifier. The installer
fires a test notification at the end; if macOS asks to allow
notifications, click **Allow**, or scheduled alerts will be silently
suppressed.

## Customize

Settings live in `~/.config/bluetooth-battery-alert/config` and are read fresh on
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
bash ~/Library/Application\ Support/bluetooth-battery-alert/check_bluetooth_battery.sh
```

Nothing happens if all devices are above threshold. To force a
notification, temporarily set `THRESHOLD=99` in
`~/.config/bluetooth-battery-alert/config`, run it again, then set it back.

## Uninstall

```bash
./uninstall.sh          # removes the agent, script copy, and logs
./uninstall.sh --purge  # also removes your settings
```

## Development

```bash
./test.sh
```

Runs an offline test suite: `ioreg` and `launchctl` are stubbed on `PATH`,
and the actual "fire a notification" call is redirected to a logging stub
(via `BTBA_NOTIFIER_BIN`) so no test ever pops a live system permission
dialog - but `install.sh` still compiles, generates an icon for, and
ad-hoc signs a real `BluetoothBatteryAlert.app` each time, exercising the
whole build pipeline for real. Everything runs against fixture data in a
throwaway `HOME`, so it needs no Bluetooth hardware and never touches your
actual launchd agents or settings. It also lints the shell scripts with
`bash -n` and `shellcheck` (install via `brew install shellcheck`; skipped
with a note if absent) and typechecks the Swift sources with `swiftc
-typecheck`. The same suite runs in GitHub Actions on every push
(`.github/workflows/ci.yml`); macOS runners ship with Xcode preinstalled,
so no extra setup is needed there.

Note the tests pin today's `ioreg` output shape via fixtures - they catch
regressions in this project's own logic, not changes Apple makes to
`ioreg` in a future macOS release.

## Credits

This project was inspired by [Freddy Reyes' blog post on macOS Bluetooth
battery alerts](https://freddyreyes.com/blog/macos-bluetooth-battery-alert/).

## Troubleshooting

Logs from scheduled runs land in `~/Library/Logs/bluetooth-battery-alert.log` and
`~/Library/Logs/bluetooth-battery-alert.err`. A "no battery-reporting devices
found" warning in the `.err` log on every run (while a Bluetooth mouse or
keyboard is connected) means `ioreg` no longer reports devices in the
expected shape. Confirm with:

```bash
ioreg -c AppleDeviceManagementHIDEventService -r -l | grep -E 'Product|BatteryPercent'
```

You should see each device's `Product` line immediately followed by its
`BatteryPercent` line. If the format has changed, update the `awk` parsing
in `check_bluetooth_battery.sh` to match, then re-run `./install.sh`.

If no notification ever appears even with a low threshold, check
System Settings > Notifications and make sure notifications are allowed
for "Bluetooth Battery Alert". If the entry is missing entirely, or the
`.err` log shows `notifier app not found`, re-run `./install.sh` to
rebuild it.
