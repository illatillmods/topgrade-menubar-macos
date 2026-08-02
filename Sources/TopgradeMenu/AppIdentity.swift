import Foundation

enum AppIdentity {
    static let bundleIdentifier = "dev.illatillmods.TopgradeMenu"
    static let statusItemAutosaveName = "dev.illatillmods.TopgradeMenu.statusItem"
    static let lastSuccessfulLaunchKey = "lastSuccessfulLaunch"
    static let lastLaunchErrorKey = "lastLaunchError"
    static let preferredTerminalBundleIdentifierKey = "preferredTerminalBundleIdentifier"
    static let reminderChangedNotification = Notification.Name(
        "dev.illatillmods.TopgradeMenu.reminderChanged"
    )

    static var defaults: UserDefaults {
        UserDefaults.standard
    }

    static func postReminderChanged() {
        DistributedNotificationCenter.default().post(
            name: reminderChangedNotification,
            object: bundleIdentifier,
            userInfo: nil
        )
    }
}
