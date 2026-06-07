import Foundation

/// Renders a coloured, human-readable report for the terminal.
///
/// The full colourised layout is implemented alongside the engine; this stub
/// provides the wiring and a minimal placeholder.
public struct TerminalReporter: Reporter {
    public init() {}

    public func render(_ result: ScanResult) -> String {
        // TODO: Coloured, grouped terminal output with file:line references.
        let status = result.passed ? "PASSED" : "FAILED"
        return "PrivacyLint — \(result.outcomes.count) checks — \(status) (report not yet implemented)"
    }
}
