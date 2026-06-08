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
        version: "0.0.1"
    )

    @Option(name: .shortAndLong, help: "Path to the Xcode project or Swift package to scan.")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Output format: terminal, json or html.")
    var format: OutputFormat = .terminal

    func run() throws {
        let projectURL = URL(fileURLWithPath: path, isDirectory: true)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError("Path is not a directory: \(projectURL.path)")
        }

        let context = try ProjectDiscovery.discover(at: projectURL)
        let registry = RuleRegistry()
        let result = registry.run(context)

        let report = format.reporter.render(result)
        print(report)
    }
}
