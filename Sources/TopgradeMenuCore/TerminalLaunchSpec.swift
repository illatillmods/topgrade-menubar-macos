import Foundation

public struct TerminalDefinition: Equatable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public enum TerminalLaunchMethod: Equatable, Sendable {
    case commandFile
    case applicationArguments([String])
    case bundledExecutable(relativePath: String, arguments: [String])
}

public enum TerminalLaunchSpec {
    public static let appleTerminalBundleIdentifier = "com.apple.Terminal"

    public static let knownTerminals = [
        TerminalDefinition(
            bundleIdentifier: appleTerminalBundleIdentifier,
            displayName: "Terminal"
        ),
        TerminalDefinition(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty"
        ),
        TerminalDefinition(
            bundleIdentifier: "com.googlecode.iterm2",
            displayName: "iTerm2"
        ),
        TerminalDefinition(
            bundleIdentifier: "dev.warp.Warp-Stable",
            displayName: "Warp"
        ),
        TerminalDefinition(
            bundleIdentifier: "net.kovidgoyal.kitty",
            displayName: "kitty"
        ),
        TerminalDefinition(
            bundleIdentifier: "com.github.wez.wezterm",
            displayName: "WezTerm"
        ),
        TerminalDefinition(
            bundleIdentifier: "org.alacritty",
            displayName: "Alacritty"
        ),
    ]

    public static func definition(for bundleIdentifier: String) -> TerminalDefinition? {
        knownTerminals.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public static func hintedBundleIdentifier(environment: [String: String]) -> String? {
        let directHints: [(String, String)] = [
            ("GHOSTTY_RESOURCES_DIR", "com.mitchellh.ghostty"),
            ("ITERM_SESSION_ID", "com.googlecode.iterm2"),
            ("WEZTERM_PANE", "com.github.wez.wezterm"),
            ("KITTY_PID", "net.kovidgoyal.kitty"),
            ("WARP_IS_LOCAL_SHELL_SESSION", "dev.warp.Warp-Stable"),
            ("ALACRITTY_LOG", "org.alacritty"),
        ]

        for (key, bundleIdentifier) in directHints
        where environment[key]?.isEmpty == false {
            return bundleIdentifier
        }

        switch environment["TERM_PROGRAM"]?.lowercased() {
        case "apple_terminal":
            return appleTerminalBundleIdentifier
        case "ghostty":
            return "com.mitchellh.ghostty"
        case "iterm.app", "iterm2":
            return "com.googlecode.iterm2"
        case "warpterminal", "warp":
            return "dev.warp.Warp-Stable"
        case "kitty":
            return "net.kovidgoyal.kitty"
        case "wezterm":
            return "com.github.wez.wezterm"
        case "alacritty":
            return "org.alacritty"
        default:
            return nil
        }
    }

    public static func automaticBundleIdentifier(
        environmentHint: String?,
        defaultHandler: String?,
        installedBundleIdentifiers: Set<String>
    ) -> String {
        if let environmentHint,
           installedBundleIdentifiers.contains(environmentHint) {
            return environmentHint
        }

        if let defaultHandler,
           defaultHandler != appleTerminalBundleIdentifier,
           installedBundleIdentifiers.contains(defaultHandler) {
            return defaultHandler
        }

        let installedThirdParty = knownTerminals
            .map(\.bundleIdentifier)
            .filter {
                $0 != appleTerminalBundleIdentifier
                    && installedBundleIdentifiers.contains($0)
            }

        if installedThirdParty.count == 1 {
            return installedThirdParty[0]
        }

        if let defaultHandler,
           installedBundleIdentifiers.contains(defaultHandler) {
            return defaultHandler
        }

        return appleTerminalBundleIdentifier
    }

    public static func method(
        for bundleIdentifier: String,
        runnerPath: String,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> TerminalLaunchMethod {
        switch bundleIdentifier {
        case "com.mitchellh.ghostty":
            let runnerName = URL(fileURLWithPath: runnerPath).lastPathComponent
            let runnerAliasPath = URL(
                fileURLWithPath: homeDirectoryPath,
                isDirectory: true
            )
                .appendingPathComponent(".TopgradeMenu.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(runnerName)
                .path
            return .applicationArguments([
                "--title=Topgrade",
                "--quit-after-last-window-closed=true",
                "--shell-integration=detect",
                "--initial-command=direct:\(runnerAliasPath) --run-topgrade",
            ])
        case "net.kovidgoyal.kitty":
            return .bundledExecutable(
                relativePath: "Contents/MacOS/kitty",
                arguments: [runnerPath, "--run-topgrade"]
            )
        case "com.github.wez.wezterm":
            return .bundledExecutable(
                relativePath: "Contents/MacOS/wezterm",
                arguments: [
                    "start",
                    "--always-new-process",
                    "--",
                    runnerPath,
                    "--run-topgrade",
                ]
            )
        case "org.alacritty":
            return .bundledExecutable(
                relativePath: "Contents/MacOS/alacritty",
                arguments: [
                    "--title",
                    "Topgrade",
                    "--command",
                    runnerPath,
                    "--run-topgrade",
                ]
            )
        default:
            return .commandFile
        }
    }
}
