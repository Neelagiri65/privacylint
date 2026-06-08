import ArgumentParser
import Foundation
import PrivacyLintCore

/// Make Core's `OutputFormat` usable as a CLI option value.
extension OutputFormat: ExpressibleByArgument {}

@main
struct PrivacyLintCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "privacylint",
        abstract: "Scan iOS and macOS projects for App Store privacy compliance issues.",
        discussion: """
        PrivacyLint checks your Xcode project against Apple's evolving privacy \
        requirements — Required Reason APIs, third-party SDK manifests, \
        PrivacyInfo.xcprivacy declarations, tracking domains and AI service \
        consent — and reports what would block your next submission.
        """,
        version: "0.1.0"
    )

    @Option(name: .shortAndLong, help: "Path to the Xcode project or Swift package to scan.")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Output format: terminal, json or html.")
    var format: OutputFormat = .terminal

    @Flag(name: .long, help: "Disable ANSI colour in terminal output.")
    var noColor: Bool = false

    @Flag(name: .long, help: "Treat warnings as errors — useful in strict CI configurations.")
    var warningsAsErrors: Bool = false

    func run() throws {
        let projectURL = URL(fileURLWithPath: path, isDirectory: true)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError("Path is not a directory: \(projectURL.path)")
        }

        let discovered = try ProjectDiscovery.discover(at: projectURL)
        let detection = PlatformDetector.detect(at: projectURL)
        let context = ScanContext(
            projectPath: discovered.projectPath,
            sourceFiles: discovered.sourceFiles,
            testFiles: discovered.testFiles,
            objcFiles: discovered.objcFiles,
            dependencyManifests: discovered.dependencyManifests,
            privacyManifests: discovered.privacyManifests,
            platforms: detection.platforms
        )
        if !detection.note.isEmpty {
            FileHandle.standardError.write(Data("note: \(detection.note)\n".utf8))
        }

        let registry = RuleRegistry()
        let result = registry.run(context)

        let reporter: Reporter
        switch format {
        case .terminal:
            // Auto-detect TTY so piping to a file or CI log strips ANSI.
            // Honour --no-color as an override.
            let stdoutIsTTY = isatty(fileno(stdout)) != 0
            reporter = TerminalReporter(useColour: stdoutIsTTY && !noColor)
        case .json:
            reporter = JSONReporter()
        case .html:
            reporter = HTMLReporter()
        }
        let report = reporter.render(result)
        print(report)

        // Drops straight into a GitHub Actions step / Xcode build phase /
        // pre-commit hook without extra plumbing. Decision logic lives on
        // ScanResult so it's unit-testable.
        if result.exitCode(warningsAsErrors: warningsAsErrors) != 0 {
            throw ExitCode.failure
        }
    }
}
