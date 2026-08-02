import AppKit
import ServiceManagement
import TopgradeMenuCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = AppIdentity.defaults
    private let terminalLauncher = TerminalLauncher()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var lastLaunchAttempt: Date?
    private var isLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshStatus()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshStatus),
            userInfo: nil,
            repeats: true
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshStatus),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(refreshStatus),
            name: AppIdentity.reminderChangedNotification,
            object: AppIdentity.bundleIdentifier
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func anotherInstanceIsRunning() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: AppIdentity.bundleIdentifier)
            .contains {
                $0.processIdentifier != ownPID
                    && $0.activationPolicy == .accessory
            }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = AppIdentity.statusItemAutosaveName

        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Topgrade updater")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(from: sender)
            return
        }

        launchTopgrade()
    }

    @objc private func launchTopgrade() {
        let now = Date()
        guard !isLaunching else {
            return
        }
        if let lastLaunchAttempt, now.timeIntervalSince(lastLaunchAttempt) < 2 {
            return
        }
        lastLaunchAttempt = now
        isLaunching = true

        terminalLauncher.launch { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.isLaunching = false
                switch result {
                case .success:
                    self.defaults.removeObject(forKey: AppIdentity.lastLaunchErrorKey)
                    self.refreshStatus()
                case let .failure(error):
                    self.reportLaunchError(error.localizedDescription)
                }
            }
        }
    }

    private func reportLaunchError(_ message: String) {
        defaults.set(message, forKey: AppIdentity.lastLaunchErrorKey)
        NSSound.beep()
        refreshStatus()
    }

    @objc private func refreshStatus() {
        guard let button = statusItem?.button else {
            return
        }

        let lastUsed = defaults.object(forKey: AppIdentity.lastSuccessfulLaunchKey) as? Date
        let due = ReminderState.isDue(lastUsed: lastUsed)
        let description = due ? "Topgrade is due" : "Topgrade is fresh"
        let image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: description
        )
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = due ? .systemRed : nil
        button.setAccessibilityLabel(description)
        button.toolTip = tooltip(lastUsed: lastUsed, due: due)
    }

    private func tooltip(lastUsed: Date?, due: Bool) -> String {
        let terminalName = terminalLauncher.selectedTerminal()?.displayName ?? "Terminal"
        var lines = [
            "Topgrade — click to run in \(terminalName)",
            "Command: \(TopgradeLaunchSpec.visibleCommand)",
        ]

        if let lastUsed {
            lines.append("Last started: \(dateFormatter.string(from: lastUsed))")
        } else {
            lines.append("Last started: never")
        }

        lines.append(due ? "Reminder: due" : "Reminder: less than 24 hours")

        if let error = defaults.string(forKey: AppIdentity.lastLaunchErrorKey) {
            lines.append("Last error: \(error)")
        }

        return lines.joined(separator: "\n")
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let runItem = NSMenuItem(
            title: "Run \(TopgradeLaunchSpec.visibleCommand)",
            action: #selector(launchTopgrade),
            keyEquivalent: ""
        )
        runItem.target = self
        menu.addItem(runItem)

        let lastUsed = defaults.object(forKey: AppIdentity.lastSuccessfulLaunchKey) as? Date
        let lastUsedTitle = lastUsed.map { "Last started: \(dateFormatter.string(from: $0))" }
            ?? "Last started: never"
        let lastUsedItem = NSMenuItem(title: lastUsedTitle, action: nil, keyEquivalent: "")
        lastUsedItem.isEnabled = false
        menu.addItem(lastUsedItem)

        menu.addItem(.separator())
        addTerminalItem(to: menu)
        addLoginItem(to: menu)

        let dueItem = NSMenuItem(
            title: "Mark reminder due",
            action: #selector(markReminderDue),
            keyEquivalent: ""
        )
        dueItem.target = self
        menu.addItem(dueItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Topgrade Menu",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }

    private func addTerminalItem(to menu: NSMenu) {
        let selectedIdentifier = defaults.string(
            forKey: AppIdentity.preferredTerminalBundleIdentifierKey
        )
        let resolvedName = terminalLauncher.selectedTerminal()?.displayName ?? "Unavailable"
        let terminalItem = NSMenuItem(
            title: "Terminal: \(resolvedName)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: "Terminal")

        let automaticName = terminalLauncher.automaticTerminal()?.displayName ?? "Terminal"
        let automaticItem = NSMenuItem(
            title: "Automatic — \(automaticName)",
            action: #selector(selectTerminal(_:)),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.representedObject = "automatic"
        automaticItem.state = selectedIdentifier == nil ? .on : .off
        submenu.addItem(automaticItem)

        submenu.addItem(.separator())
        for terminal in terminalLauncher.installedTerminals() {
            let item = NSMenuItem(
                title: terminal.displayName,
                action: #selector(selectTerminal(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = terminal.bundleIdentifier
            item.state = selectedIdentifier == terminal.bundleIdentifier ? .on : .off
            submenu.addItem(item)
        }

        terminalItem.submenu = submenu
        menu.addItem(terminalItem)
    }

    @objc private func selectTerminal(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? String else {
            return
        }

        do {
            try terminalLauncher.setPreferredTerminal(
                bundleIdentifier: selection == "automatic" ? nil : selection
            )
            defaults.removeObject(forKey: AppIdentity.lastLaunchErrorKey)
        } catch {
            reportLaunchError(error.localizedDescription)
            return
        }
        refreshStatus()
    }

    private func addLoginItem(to menu: NSMenu) {
        switch SMAppService.mainApp.status {
        case .enabled:
            let item = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            item.state = .on
            item.target = self
            menu.addItem(item)
        case .requiresApproval:
            let item = NSMenuItem(
                title: "Approve Launch at Login…",
                action: #selector(openLoginItemsSettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        case .notRegistered, .notFound:
            let item = NSMenuItem(
                title: "Enable Launch at Login",
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        @unknown default:
            let item = NSMenuItem(
                title: "Launch-at-login status unknown",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            defaults.removeObject(forKey: AppIdentity.lastLaunchErrorKey)
        } catch {
            defaults.set(
                "Launch at Login change failed: \(error.localizedDescription)",
                forKey: AppIdentity.lastLaunchErrorKey
            )
            NSSound.beep()
        }
        refreshStatus()
    }

    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func markReminderDue() {
        defaults.removeObject(forKey: AppIdentity.lastSuccessfulLaunchKey)
        defaults.removeObject(forKey: AppIdentity.lastLaunchErrorKey)
        refreshStatus()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
