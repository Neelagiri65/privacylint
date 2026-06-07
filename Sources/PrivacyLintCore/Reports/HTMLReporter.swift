import Foundation

/// Renders a self-contained HTML report suitable for sharing or CI artefacts.
///
/// The full templated report is implemented alongside the engine; this stub
/// provides the wiring and a minimal placeholder document.
public struct HTMLReporter: Reporter {
    public init() {}

    public func render(_ result: ScanResult) -> String {
        // TODO: Templated HTML report with per-check sections and remediation.
        let status = result.passed ? "Passed" : "Failed"
        return """
        <!DOCTYPE html>
        <html lang="en-GB">
        <head><meta charset="utf-8"><title>PrivacyLint Report</title></head>
        <body>
          <h1>PrivacyLint Report</h1>
          <p>Checks run: \(result.outcomes.count) — Status: \(status)</p>
          <p><em>Detailed report not yet implemented.</em></p>
        </body>
        </html>
        """
    }
}
