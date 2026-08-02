import AppKit
import Darwin
import ServiceManagement
import TopgradeMenuCore

private enum CommandError: LocalizedError {
    case topgradeMissing
    case alreadyRunning
    case lockCreationFailed(String)
    case terminalControlFailed(String)

    var errorDescription: String? {
        switch self {
        case .topgradeMissing:
            return "Topgrade is missing or no longer executable. Reinstall Topgrade, then rerun Scripts/install.sh."
        case .alreadyRunning:
            return "Another Topgrade session launched by Topgrade Menu is already running."
        case let .lockCreationFailed(detail):
            return "Could not create the per-user Topgrade lock: \(detail)"
        case let .terminalControlFailed(detail):
            return "Could not give Topgrade control of the terminal: \(detail)"
        }
    }
}

private final class TopgradeRunLock {
    private let descriptor: Int32

    init() throws {
        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Topgrade Menu", isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let lockPath = supportDirectory.appendingPathComponent("run.lock").path
        let openedDescriptor = lockPath.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard openedDescriptor >= 0 else {
            throw CommandError.lockCreationFailed(String(cString: strerror(errno)))
        }
        guard Darwin.lockf(openedDescriptor, F_TLOCK, 0) == 0 else {
            let lockError = errno
            Darwin.close(openedDescriptor)
            if lockError == EACCES || lockError == EAGAIN {
                throw CommandError.alreadyRunning
            }
            throw CommandError.lockCreationFailed(String(cString: strerror(lockError)))
        }

        descriptor = openedDescriptor
    }

    deinit {
        _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        Darwin.close(descriptor)
    }
}

private func loginStatusDescription(_ status: SMAppService.Status) -> String {
    switch status {
    case .notRegistered:
        return "not registered"
    case .enabled:
        return "enabled"
    case .requiresApproval:
        return "requires approval"
    case .notFound:
        return "not found"
    @unknown default:
        return "unknown (\(status.rawValue))"
    }
}

private func embeddedTopgradePath() -> String? {
    guard let pathURL = Bundle.main.url(forResource: "topgrade-path", withExtension: nil),
          let contents = try? String(contentsOf: pathURL, encoding: .utf8)
    else {
        return nil
    }
    return TopgradeLaunchSpec.validatedExecutablePath(contents)
}

private func embeddedEnvironmentPath() -> String? {
    guard let pathURL = Bundle.main.url(
        forResource: "topgrade-environment-path",
        withExtension: nil
    ), let contents = try? String(contentsOf: pathURL, encoding: .utf8)
    else {
        return nil
    }
    return TopgradeLaunchSpec.sanitizedEnvironmentPath(contents)
}

private func resolvedTopgradeExecutable() -> String? {
    let candidates = TopgradeLaunchSpec.executableCandidates(
        embeddedPath: embeddedTopgradePath(),
        environmentPath: ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
    )

    return candidates.first { candidate in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: candidate,
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: candidate)
    }
}

private func shellDisplay(_ value: String) -> String {
    guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
        return value
    }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func pauseBeforeClosing() {
    guard Darwin.isatty(STDIN_FILENO) == 1 else {
        return
    }
    print("Press Return to close this window.", terminator: " ")
    _ = readLine()
}

private struct TerminalForegroundLease {
    let fileDescriptor: Int32
    let originalProcessGroup: pid_t

    static func acquire(for process: Process) throws -> TerminalForegroundLease? {
        let fileDescriptor = STDIN_FILENO
        guard Darwin.isatty(fileDescriptor) == 1 else {
            return nil
        }

        let originalProcessGroup = Darwin.tcgetpgrp(fileDescriptor)
        guard originalProcessGroup >= 0 else {
            throw CommandError.terminalControlFailed(currentErrorDescription())
        }

        let childProcessGroup = Darwin.getpgid(process.processIdentifier)
        guard childProcessGroup >= 0 else {
            throw CommandError.terminalControlFailed(currentErrorDescription())
        }

        guard setForegroundProcessGroup(
            childProcessGroup,
            fileDescriptor: fileDescriptor
        ) else {
            throw CommandError.terminalControlFailed(currentErrorDescription())
        }

        if Darwin.kill(-childProcessGroup, SIGCONT) != 0 && errno != ESRCH {
            let continueError = errno
            _ = setForegroundProcessGroup(
                originalProcessGroup,
                fileDescriptor: fileDescriptor
            )
            throw CommandError.terminalControlFailed(errorDescription(continueError))
        }

        return TerminalForegroundLease(
            fileDescriptor: fileDescriptor,
            originalProcessGroup: originalProcessGroup
        )
    }

    func restore() throws {
        guard Self.setForegroundProcessGroup(
            originalProcessGroup,
            fileDescriptor: fileDescriptor
        ) else {
            throw CommandError.terminalControlFailed(
                Self.currentErrorDescription()
            )
        }
    }

    private static func setForegroundProcessGroup(
        _ processGroup: pid_t,
        fileDescriptor: Int32
    ) -> Bool {
        let previousHandler = Darwin.signal(SIGTTOU, SIG_IGN)
        defer { _ = Darwin.signal(SIGTTOU, previousHandler) }
        return Darwin.tcsetpgrp(fileDescriptor, processGroup) == 0
    }

    private static func currentErrorDescription() -> String {
        errorDescription(errno)
    }

    private static func errorDescription(_ errorNumber: Int32) -> String {
        String(cString: strerror(errorNumber))
    }
}

private func runTopgrade() -> Int32 {
    do {
        guard let executable = resolvedTopgradeExecutable() else {
            throw CommandError.topgradeMissing
        }
        let runLock = try TopgradeRunLock()

        print("Running: \(shellDisplay(executable)) -r damp\n")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = TopgradeLaunchSpec.arguments
        if let environmentPath = embeddedEnvironmentPath() {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = environmentPath
            process.environment = environment
        }
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()

        let foregroundLease: TerminalForegroundLease?
        do {
            foregroundLease = try TerminalForegroundLease.acquire(for: process)
        } catch {
            let childProcessGroup = Darwin.getpgid(process.processIdentifier)
            if childProcessGroup > 0 && childProcessGroup != Darwin.getpgrp() {
                _ = Darwin.kill(-childProcessGroup, SIGKILL)
            } else if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw error
        }

        let defaults = AppIdentity.defaults
        defaults.set(Date(), forKey: AppIdentity.lastSuccessfulLaunchKey)
        defaults.removeObject(forKey: AppIdentity.lastLaunchErrorKey)
        defaults.synchronize()
        AppIdentity.postReminderChanged()

        process.waitUntilExit()
        let status = process.terminationStatus
        withExtendedLifetime(runLock) {}
        do {
            try foregroundLease?.restore()
        } catch {
            fputs("Topgrade Menu: \(error.localizedDescription)\n", stderr)
            return 75
        }
        print("\nTopgrade exited with status \(status).")
        pauseBeforeClosing()
        return status
    } catch {
        fputs("Topgrade Menu: \(error.localizedDescription)\n", stderr)
        pauseBeforeClosing()
        return error is CommandError ? 75 : 1
    }
}

@MainActor
private func runningMenuApps() -> [NSRunningApplication] {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication
        .runningApplications(withBundleIdentifier: AppIdentity.bundleIdentifier)
        .filter {
            $0.processIdentifier != ownPID
                && $0.activationPolicy == .accessory
        }
}

@MainActor
private func quitRunningMenuApp() -> Int32 {
    let running = runningMenuApps()
    let requested = running.filter { $0.terminate() }.count
    print("Quit requested for \(requested) running Topgrade Menu instance(s).")
    return requested == running.count ? 0 : 1
}

@MainActor
private func printStatus() -> Int32 {
    let defaults = AppIdentity.defaults
    let lastUsed = defaults.object(forKey: AppIdentity.lastSuccessfulLaunchKey) as? Date
    let due = ReminderState.isDue(lastUsed: lastUsed)
    let launcher = TerminalLauncher()

    print("Reminder: \(due ? "due" : "fresh")")
    print("Last started: \(lastUsed?.description ?? "never")")
    print("Launch at Login: \(loginStatusDescription(SMAppService.mainApp.status))")
    print("Terminal preference: \(defaults.string(forKey: AppIdentity.preferredTerminalBundleIdentifierKey) ?? "automatic")")
    print("Resolved terminal: \(launcher.selectedTerminal()?.displayName ?? "unavailable")")
    print("Topgrade: \(resolvedTopgradeExecutable() ?? "missing")")
    print("Command: \(TopgradeLaunchSpec.visibleCommand)")
    if let error = defaults.string(forKey: AppIdentity.lastLaunchErrorKey) {
        print("Last error: \(error)")
    }
    return 0
}

@MainActor
private func handleCommandLineMode() -> Int32? {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let argument = arguments.first else {
        return nil
    }
    if argument.hasPrefix("-psn_") {
        return nil
    }

    let defaults = AppIdentity.defaults

    switch argument {
    case "--run-topgrade":
        guard arguments.count == 1 else {
            print("Usage: TopgradeMenu --run-topgrade")
            return 64
        }
        return runTopgrade()
    case "--mark-used-now":
        defaults.set(Date(), forKey: AppIdentity.lastSuccessfulLaunchKey)
        defaults.removeObject(forKey: AppIdentity.lastLaunchErrorKey)
        defaults.synchronize()
        AppIdentity.postReminderChanged()
        print("Marked Topgrade as started now.")
        return 0
    case "--mark-due":
        defaults.removeObject(forKey: AppIdentity.lastSuccessfulLaunchKey)
        defaults.synchronize()
        AppIdentity.postReminderChanged()
        print("Marked the Topgrade reminder as due.")
        return 0
    case "--register-login":
        do {
            let status = SMAppService.mainApp.status
            if status == .notRegistered || status == .notFound {
                try SMAppService.mainApp.register()
            }
            let finalStatus = SMAppService.mainApp.status
            print("Launch at Login: \(loginStatusDescription(finalStatus))")
            return finalStatus == .enabled || finalStatus == .requiresApproval ? 0 : 1
        } catch {
            print("Launch at Login registration failed: \(error.localizedDescription)")
            return 1
        }
    case "--unregister-login":
        do {
            let status = SMAppService.mainApp.status
            if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            let finalStatus = SMAppService.mainApp.status
            print("Launch at Login: \(loginStatusDescription(finalStatus))")
            return finalStatus == .notRegistered || finalStatus == .notFound ? 0 : 1
        } catch {
            print("Launch at Login removal failed: \(error.localizedDescription)")
            return 1
        }
    case "--set-terminal":
        guard arguments.count == 2 else {
            print("Usage: TopgradeMenu --set-terminal automatic|BUNDLE_ID")
            return 64
        }
        let launcher = TerminalLauncher()
        do {
            try launcher.setPreferredTerminal(
                bundleIdentifier: arguments[1] == "automatic" ? nil : arguments[1]
            )
            print("Terminal: \(launcher.selectedTerminal()?.displayName ?? "unavailable")")
            return 0
        } catch {
            print("Terminal selection failed: \(error.localizedDescription)")
            return 1
        }
    case "--set-terminal-from-environment":
        let launcher = TerminalLauncher()
        if let terminal = launcher.selectFromEnvironment(
            ProcessInfo.processInfo.environment
        ) {
            print("Terminal detected: \(terminal.displayName)")
        } else {
            print("Terminal detected: none; using Automatic")
        }
        return 0
    case "--quit":
        return quitRunningMenuApp()
    case "--is-running":
        let count = runningMenuApps().count
        print("Running menu-bar instances: \(count)")
        return count > 0 ? 0 : 1
    case "--status":
        return printStatus()
    case "--help":
        print("""
        Usage: TopgradeMenu [OPTION]
          --status                         Show read-only local status
          --set-terminal automatic|ID      Set the preferred terminal
          --register-login                 Enable launch at login
          --unregister-login               Disable launch at login
          --mark-due                       Mark the 24-hour reminder due
          --quit                           Quit the menu-bar app
        """)
        return 0
    default:
        print("Unknown option: \(argument). Run with --help for supported options.")
        return 64
    }
}

MainActor.assumeIsolated {
    if let exitCode = handleCommandLineMode() {
        exit(exitCode)
    } else {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
