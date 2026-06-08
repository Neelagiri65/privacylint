import Foundation

/// Detects which Apple platforms a project targets so the scanner pipeline
/// can apply or skip checks accordingly.
///
/// v1 supports Swift Package Manager projects via `swift package describe
/// --type json` — the canonical, parser-version-independent source of the
/// `platforms` array. `.xcodeproj` parsing is out of scope (v2); when a
/// project has no `Package.swift`, detection returns an empty set, which
/// `ScanContext` treats as "unknown — assume every platform applies."
public enum PlatformDetector {
    /// The result of a detection attempt.
    public struct Result: Sendable {
        public let platforms: Set<ApplePlatform>
        /// One-line, user-facing note when detection succeeded with caveats
        /// (unknown SPM platform name, fallback used, etc.) or failed
        /// gracefully. Empty string when there's nothing to report.
        public let note: String
    }

    public static func detect(at projectPath: URL) -> Result {
        let packageSwift = projectPath.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageSwift.path) {
            return detectFromSPM(at: projectPath)
        }

        let xcodeprojExists = (try? FileManager.default.contentsOfDirectory(atPath: projectPath.path))?
            .contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") } ?? false
        if xcodeprojExists {
            return Result(
                platforms: [],
                note: "Detected an Xcode project. v1 only parses Swift Package Manager manifests, so platform detection was skipped — every scanner will run. Add `swift package` support in a separate run if needed."
            )
        }

        return Result(platforms: [], note: "")
    }

    // MARK: - SPM

    private static func detectFromSPM(at projectPath: URL) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["swift", "package", "describe", "--type", "json"]
        proc.currentDirectoryURL = projectPath

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        do {
            try proc.run()
        } catch {
            return Result(
                platforms: [],
                note: "Could not run `swift package describe`: \(error.localizedDescription). Falling back to scanning every platform."
            )
        }

        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            return Result(
                platforms: [],
                note: "`swift package describe` exited with status \(proc.terminationStatus). Falling back to scanning every platform."
            )
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return parseDescribeJSON(data)
    }

    /// Parse the output of `swift package describe --type json`. Exposed
    /// `internal` so tests can feed fixture JSON without shelling out to
    /// `swift package` — running it reentrantly inside `swift test` deadlocks
    /// on the SPM build lock.
    static func parseDescribeJSON(_ data: Data) -> Result {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["platforms"] as? [[String: Any]] else {
            return Result(
                platforms: [],
                note: "`swift package describe` produced output PrivacyLint could not parse. Falling back to scanning every platform."
            )
        }

        var detected: Set<ApplePlatform> = []
        var unknown: [String] = []
        for entry in raw {
            guard let name = entry["name"] as? String else { continue }
            if let mapped = ApplePlatform.fromSPMName(name) {
                detected.insert(mapped)
            } else {
                unknown.append(name)
            }
        }

        var note = ""
        if !unknown.isEmpty {
            note = "Encountered platform names PrivacyLint does not recognise: \(unknown.joined(separator: ", ")). They were ignored; everything else was scanned normally."
        }

        // An empty platforms array in Package.swift means "use SPM defaults"
        // — i.e. all platforms. Treat as unknown so we don't silently turn
        // every check off on a library that ships universally.
        if detected.isEmpty {
            return Result(
                platforms: [],
                note: note.isEmpty
                    ? "Package.swift declares no explicit `platforms:` — every scanner will run."
                    : note
            )
        }

        return Result(platforms: detected, note: note)
    }
}
