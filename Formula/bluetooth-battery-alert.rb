class BluetoothBatteryAlert < Formula
  desc "Native macOS alert when a Bluetooth mouse/keyboard battery runs low"
  homepage "https://github.com/fancygits/bluetooth-battery-alert"
  url "https://github.com/fancygits/bluetooth-battery-alert.git",
      tag:      "v1.0.0",
      revision: "2b1882106b901677af040c25567534408e0b4e68"
  version "1.0.0"
  license "MIT"

  depends_on :macos

  def install
    # check_bluetooth_battery.sh, install.sh, and uninstall.sh all resolve
    # sibling files (notifier/, each other) relative to their own location,
    # so staging this whole set unmodified under libexec works the same
    # way a git clone does - no path rewriting needed.
    libexec.install "check_bluetooth_battery.sh", "install.sh", "uninstall.sh", "notifier"

    (bin/"bluetooth-battery-alert").write <<~SH
      #!/bin/bash
      set -euo pipefail
      case "${1:-}" in
        install)   shift; exec "#{libexec}/install.sh" "$@" ;;
        uninstall) shift; exec "#{libexec}/uninstall.sh" "$@" ;;
        *)
          echo "Usage: bluetooth-battery-alert <install|uninstall> [options]" >&2
          exit 64
          ;;
      esac
    SH
    (bin/"bluetooth-battery-alert").chmod 0755
  end

  def caveats
    <<~EOS
      To finish setup - build and sign the notification helper, and register
      the scheduled check - run:
        bluetooth-battery-alert install

      The first time it runs, macOS will ask you to allow notifications for
      "Bluetooth Battery Alert" - click Allow, or alerts will be silently
      suppressed.

      Customize the threshold and schedule with flags, e.g.:
        bluetooth-battery-alert install --threshold 15 --hour 16 --minute 30 --days mon,wed,fri

      Before removing this formula, run this first to unregister the
      scheduled check and remove the notifier - `brew uninstall` on its own
      only removes this command, not the LaunchAgent it registered:
        bluetooth-battery-alert uninstall
        brew uninstall bluetooth-battery-alert
    EOS
  end

  test do
    assert_match "Usage", shell_output("#{bin}/bluetooth-battery-alert install --help")
    output = shell_output("#{bin}/bluetooth-battery-alert bogus 2>&1", 64)
    assert_match "Usage: bluetooth-battery-alert", output
  end
end
