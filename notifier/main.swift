// Posts a native notification via UserNotifications. Run as the executable
// inside BluetoothBatteryAlert.app (built by install.sh), never invoked
// directly - this is what gives the notification our own name/icon and a
// harmless click target, instead of Script Editor's (which is what plain
// `osascript -e 'display notification'` attributes notifications to).
//
// Usage: BluetoothBatteryAlert <title> <body> [sound]
//
// Arguments are passed as plain argv strings, never parsed as script or
// shell source, so a maliciously named Bluetooth device can't inject code
// here the way it could via an AppleScript string built by concatenation.

import Cocoa
import UserNotifications

// Initializing the shared NSApplication (without running its event loop)
// is required for UNUserNotificationCenter to resolve this process's
// bundle identity - without it, notification calls silently fail.
_ = NSApplication.shared

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: BluetoothBatteryAlert <title> <body> [sound]\n".data(using: .utf8)!)
    exit(64)
}

let title = arguments[1]
let body = arguments[2]
let soundName = arguments.count > 3 ? arguments[3] : "Glass"

let center = UNUserNotificationCenter.current()
let authSemaphore = DispatchSemaphore(value: 0)
var authGranted = false

center.requestAuthorization(options: [.alert, .sound]) { granted, error in
    authGranted = granted
    if let error = error {
        FileHandle.standardError.write("authorization error: \(error)\n".data(using: .utf8)!)
    }
    authSemaphore.signal()
}
authSemaphore.wait()

guard authGranted else {
    FileHandle.standardError.write("notifications not authorized - enable in System Settings > Notifications > Bluetooth Battery Alert\n".data(using: .utf8)!)
    exit(1)
}

let content = UNMutableNotificationContent()
content.title = title
content.body = body
content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundName).aiff"))

let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

let deliverSemaphore = DispatchSemaphore(value: 0)
var deliverError: Error?
center.add(request) { error in
    deliverError = error
    deliverSemaphore.signal()
}
deliverSemaphore.wait()

if let deliverError = deliverError {
    FileHandle.standardError.write("failed to deliver notification: \(deliverError)\n".data(using: .utf8)!)
    exit(1)
}
