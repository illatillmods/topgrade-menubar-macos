import Darwin
import Foundation
import TopgradeMenuCore

var passed = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else {
        fputs("not ok - \(name)\n", stderr)
        exit(1)
    }

    passed += 1
    print("ok - \(name)")
}

let now = Date(timeIntervalSince1970: 2_000_000_000)

check(
    ReminderState.isDue(lastUsed: nil, now: now),
    "no previous launch is due"
)
check(
    !ReminderState.isDue(
        lastUsed: now.addingTimeInterval(-(ReminderState.dueAfter - 1)),
        now: now
    ),
    "one second before 24 hours is fresh"
)
check(
    ReminderState.isDue(
        lastUsed: now.addingTimeInterval(-ReminderState.dueAfter),
        now: now
    ),
    "exactly 24 hours is due"
)
check(
    !ReminderState.isDue(lastUsed: now.addingTimeInterval(60), now: now),
    "a future timestamp caused by clock correction stays fresh"
)

check(
    TopgradeLaunchSpec.visibleCommand == "topgrade -r damp"
        && TopgradeLaunchSpec.arguments == ["-r", "damp"],
    "Topgrade invocation is the fixed damp command"
)
check(
    TopgradeLaunchSpec.validatedExecutablePath(" /opt/homebrew/bin/topgrade\n")
        == "/opt/homebrew/bin/topgrade",
    "an absolute embedded executable path is normalized"
)
check(
    TopgradeLaunchSpec.validatedExecutablePath("topgrade") == nil
        && TopgradeLaunchSpec.validatedExecutablePath("/tmp/top\ngrade") == nil
        && TopgradeLaunchSpec.validatedExecutablePath("/") == nil,
    "relative, multiline, and root executable paths are rejected"
)

let candidates = TopgradeLaunchSpec.executableCandidates(
    embeddedPath: "/custom/Topgrade Folder/topgrade\n",
    environmentPath: ":relative:/custom/bin:/opt/homebrew/bin:/custom/bin",
    homeDirectory: "/Users/example"
)
check(
    candidates.first == "/custom/Topgrade Folder/topgrade",
    "the installer-recorded executable has priority"
)
check(
    candidates.contains("/custom/bin/topgrade")
        && !candidates.contains("relative/topgrade")
        && Set(candidates).count == candidates.count,
    "PATH candidates are absolute and deduplicated"
)
check(
    candidates.contains("/opt/homebrew/bin/topgrade")
        && candidates.contains("/usr/local/bin/topgrade")
        && candidates.contains("/opt/local/bin/topgrade")
        && candidates.contains("/Users/example/.cargo/bin/topgrade")
        && candidates.contains("/Users/example/.local/bin/topgrade")
        && candidates.contains("/Users/example/.nix-profile/bin/topgrade"),
    "common ARM, Intel, MacPorts, Cargo, local, and Nix paths are covered"
)
check(
    TopgradeLaunchSpec.sanitizedEnvironmentPath(
        ":relative:/opt/homebrew/bin:/Users/example/My Tools:/opt/homebrew/bin:/bad\npath:/usr/bin\n"
    ) == "/opt/homebrew/bin:/Users/example/My Tools:/usr/bin",
    "captured PATH keeps absolute entries while rejecting unsafe and duplicate entries"
)
check(
    TopgradeLaunchSpec.sanitizedEnvironmentPath(":relative:") == nil,
    "a captured PATH with no absolute entries is rejected"
)

let expectedHints = [
    ("TERM_PROGRAM", "Apple_Terminal", "com.apple.Terminal"),
    ("TERM_PROGRAM", "ghostty", "com.mitchellh.ghostty"),
    ("ITERM_SESSION_ID", "session", "com.googlecode.iterm2"),
    ("WARP_IS_LOCAL_SHELL_SESSION", "1", "dev.warp.Warp-Stable"),
    ("KITTY_PID", "42", "net.kovidgoyal.kitty"),
    ("WEZTERM_PANE", "1", "com.github.wez.wezterm"),
    ("ALACRITTY_LOG", "/tmp/log", "org.alacritty"),
]
for (key, value, expected) in expectedHints {
    check(
        TerminalLaunchSpec.hintedBundleIdentifier(environment: [key: value]) == expected,
        "\(expected) environment hint is recognized"
    )
}
check(
    TerminalLaunchSpec.hintedBundleIdentifier(environment: [:]) == nil,
    "an unknown environment provides no terminal hint"
)

let terminal = TerminalLaunchSpec.appleTerminalBundleIdentifier
let ghostty = "com.mitchellh.ghostty"
let iterm = "com.googlecode.iterm2"
check(
    TerminalLaunchSpec.automaticBundleIdentifier(
        environmentHint: ghostty,
        defaultHandler: terminal,
        installedBundleIdentifiers: [terminal, ghostty]
    ) == ghostty,
    "an installed environment hint takes priority"
)
check(
    TerminalLaunchSpec.automaticBundleIdentifier(
        environmentHint: "missing.terminal",
        defaultHandler: iterm,
        installedBundleIdentifiers: [terminal, iterm]
    ) == iterm,
    "an installed third-party command handler is selected"
)
check(
    TerminalLaunchSpec.automaticBundleIdentifier(
        environmentHint: nil,
        defaultHandler: terminal,
        installedBundleIdentifiers: [terminal, ghostty]
    ) == ghostty,
    "a sole installed third-party terminal is selected"
)
check(
    TerminalLaunchSpec.automaticBundleIdentifier(
        environmentHint: nil,
        defaultHandler: "com.apple.TextEdit",
        installedBundleIdentifiers: [terminal]
    ) == terminal,
    "an unknown or nonterminal handler falls back to Terminal"
)

check(
    TerminalLaunchSpec.method(for: terminal, runnerPath: "/App/Runner") == .commandFile
        && TerminalLaunchSpec.method(for: iterm, runnerPath: "/App/Runner") == .commandFile
        && TerminalLaunchSpec.method(for: "dev.warp.Warp-Stable", runnerPath: "/App/Runner") == .commandFile,
    "Terminal, iTerm2, and Warp open the sealed command file"
)
check(
    TerminalLaunchSpec.method(for: ghostty, runnerPath: "/App/Runner")
        == .applicationArguments([
            "--title=Topgrade",
            "-e",
            "/App/Runner",
            "--run-topgrade",
        ]),
    "Ghostty receives the runner as fixed argv"
)
check(
    TerminalLaunchSpec.method(for: "net.kovidgoyal.kitty", runnerPath: "/App/Runner")
        == .bundledExecutable(
            relativePath: "Contents/MacOS/kitty",
            arguments: ["/App/Runner", "--run-topgrade"]
        ),
    "kitty receives the runner as fixed argv"
)
check(
    TerminalLaunchSpec.method(for: "com.github.wez.wezterm", runnerPath: "/App/Runner")
        == .bundledExecutable(
            relativePath: "Contents/MacOS/wezterm",
            arguments: [
                "start",
                "--always-new-process",
                "--",
                "/App/Runner",
                "--run-topgrade",
            ]
        ),
    "WezTerm receives the runner as fixed argv"
)
check(
    TerminalLaunchSpec.method(for: "org.alacritty", runnerPath: "/App/Runner")
        == .bundledExecutable(
            relativePath: "Contents/MacOS/alacritty",
            arguments: [
                "--title",
                "Topgrade",
                "--command",
                "/App/Runner",
                "--run-topgrade",
            ]
        ),
    "Alacritty receives the runner as fixed argv"
)
check(
    Set(TerminalLaunchSpec.knownTerminals.map(\.bundleIdentifier)).count == 7,
    "the seven supported terminal identifiers are unique"
)

print("\(passed)/\(passed) checks passed")
