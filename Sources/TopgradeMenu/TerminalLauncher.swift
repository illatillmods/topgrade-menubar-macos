import AppKit
import TopgradeMenuCore

struct ResolvedTerminal {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL
    let launchMethod: TerminalLaunchMethod
}

enum TerminalLauncherError: LocalizedError {
    case missingRunner
    case noSupportedTerminal
    case missingTerminalExecutable(String)

    var errorDescription: String? {
        switch self {
        case .missingRunner:
            return "The signed Topgrade runner is missing from the app bundle. Reinstall the app."
        case .noSupportedTerminal:
            return "No supported terminal could be found. Terminal.app should be present on every supported Mac."
        case let .missingTerminalExecutable(name):
            return "The executable inside \(name) could not be found."
        }
    }
}

@MainActor
final class TerminalLauncher {
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private var childProcesses: [Int32: Process] = [:]

    init(
        workspace: NSWorkspace = .shared,
        defaults: UserDefaults = AppIdentity.defaults
    ) {
        self.workspace = workspace
        self.defaults = defaults
    }

    var commandFileURL: URL? {
        Bundle.main.url(forResource: "Run Topgrade", withExtension: "command")
    }

    var runnerURL: URL? {
        Bundle.main.executableURL
    }

    func installedTerminals() -> [ResolvedTerminal] {
        TerminalLaunchSpec.knownTerminals.compactMap { definition in
            guard let applicationURL = workspace.urlForApplication(
                withBundleIdentifier: definition.bundleIdentifier
            ), let runnerURL else {
                return nil
            }

            return ResolvedTerminal(
                bundleIdentifier: definition.bundleIdentifier,
                displayName: definition.displayName,
                applicationURL: applicationURL,
                launchMethod: TerminalLaunchSpec.method(
                    for: definition.bundleIdentifier,
                    runnerPath: runnerURL.path
                )
            )
        }
    }

    func automaticTerminal() -> ResolvedTerminal? {
        guard let commandFileURL else {
            return nil
        }

        let installed = installedTerminals()
        let installedIdentifiers = Set(installed.map(\.bundleIdentifier))
        let defaultURL = workspace.urlForApplication(toOpen: commandFileURL)
        let defaultIdentifier = defaultURL.flatMap {
            Bundle(url: $0)?.bundleIdentifier
        }
        let selectedIdentifier = TerminalLaunchSpec.automaticBundleIdentifier(
            environmentHint: nil,
            defaultHandler: defaultIdentifier,
            installedBundleIdentifiers: installedIdentifiers
        )

        return installed.first { $0.bundleIdentifier == selectedIdentifier }
            ?? installed.first {
                $0.bundleIdentifier == TerminalLaunchSpec.appleTerminalBundleIdentifier
            }
    }

    func selectedTerminal() -> ResolvedTerminal? {
        if let preferredIdentifier = defaults.string(
            forKey: AppIdentity.preferredTerminalBundleIdentifierKey
        ), let preferred = installedTerminals().first(where: {
            $0.bundleIdentifier == preferredIdentifier
        }) {
            return preferred
        }

        return automaticTerminal()
    }

    func setPreferredTerminal(bundleIdentifier: String?) throws {
        guard let bundleIdentifier else {
            defaults.removeObject(forKey: AppIdentity.preferredTerminalBundleIdentifierKey)
            return
        }

        guard installedTerminals().contains(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            throw TerminalLauncherError.noSupportedTerminal
        }

        defaults.set(
            bundleIdentifier,
            forKey: AppIdentity.preferredTerminalBundleIdentifierKey
        )
    }

    func selectFromEnvironment(_ environment: [String: String]) -> ResolvedTerminal? {
        guard let hintedIdentifier = TerminalLaunchSpec.hintedBundleIdentifier(
            environment: environment
        ), let terminal = installedTerminals().first(where: {
            $0.bundleIdentifier == hintedIdentifier
        }) else {
            return nil
        }

        defaults.set(
            terminal.bundleIdentifier,
            forKey: AppIdentity.preferredTerminalBundleIdentifierKey
        )
        return terminal
    }

    func launch(
        completion: @escaping (Result<ResolvedTerminal, Error>) -> Void
    ) {
        guard let commandFileURL, runnerURL != nil else {
            completion(.failure(TerminalLauncherError.missingRunner))
            return
        }
        guard let terminal = selectedTerminal() else {
            completion(.failure(TerminalLauncherError.noSupportedTerminal))
            return
        }

        switch terminal.launchMethod {
        case .commandFile:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            workspace.open(
                [commandFileURL],
                withApplicationAt: terminal.applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(terminal))
                }
            }

        case let .applicationArguments(arguments):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            configuration.createsNewApplicationInstance = true
            configuration.arguments = arguments
            workspace.openApplication(
                at: terminal.applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(terminal))
                }
            }

        case let .bundledExecutable(relativePath, arguments):
            let executableURL = terminal.applicationURL
                .appendingPathComponent(relativePath)
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                completion(.failure(
                    TerminalLauncherError.missingTerminalExecutable(terminal.displayName)
                ))
                return
            }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.terminationHandler = { [weak self] finishedProcess in
                Task { @MainActor [weak self] in
                    self?.childProcesses.removeValue(
                        forKey: finishedProcess.processIdentifier
                    )
                }
            }

            do {
                try process.run()
                childProcesses[process.processIdentifier] = process
                completion(.success(terminal))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
