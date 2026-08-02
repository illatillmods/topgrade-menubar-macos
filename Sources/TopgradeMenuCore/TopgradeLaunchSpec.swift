import Foundation

public enum TopgradeLaunchSpec {
    public static let visibleCommand = "topgrade -r damp"
    public static let arguments = ["-r", "damp"]

    public static func validatedExecutablePath(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("/"),
              !value.contains("\n"),
              !value.contains("\r"),
              !value.contains("\0"),
              value != "/"
        else {
            return nil
        }
        return value
    }

    public static func executableCandidates(
        embeddedPath: String?,
        environmentPath: String?,
        homeDirectory: String
    ) -> [String] {
        var candidates: [String] = []

        func append(_ path: String?) {
            guard let path,
                  let validPath = validatedExecutablePath(path),
                  !candidates.contains(validPath)
            else {
                return
            }
            candidates.append(validPath)
        }

        append(embeddedPath)

        environmentPath?
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .forEach { append("\($0)/topgrade") }

        [
            "/opt/homebrew/bin/topgrade",
            "/usr/local/bin/topgrade",
            "/opt/local/bin/topgrade",
            "\(homeDirectory)/.cargo/bin/topgrade",
            "\(homeDirectory)/.local/bin/topgrade",
            "\(homeDirectory)/.nix-profile/bin/topgrade",
        ].forEach { append($0) }

        return candidates
    }

    public static func sanitizedEnvironmentPath(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let normalizedValue = rawValue.trimmingCharacters(in: .newlines)
        var entries: [String] = []
        for entry in normalizedValue.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init) {
            guard entry.hasPrefix("/"),
                  !entry.contains("\n"),
                  !entry.contains("\r"),
                  !entry.contains("\0"),
                  !entries.contains(entry)
            else {
                continue
            }
            entries.append(entry)
        }

        return entries.isEmpty ? nil : entries.joined(separator: ":")
    }
}
