import Foundation

/// The output format requested for a report.
///
/// Defined in Core (free of any ArgumentParser dependency); the CLI layer
/// conforms it to `ExpressibleByArgument`.
public enum OutputFormat: String, Codable, Sendable, CaseIterable {
    case terminal
    case json
    case html
}

/// Renders a ``ScanResult`` into a textual report.
public protocol Reporter {
    func render(_ result: ScanResult) -> String
}

public extension OutputFormat {
    /// The reporter that produces this format.
    var reporter: Reporter {
        switch self {
        case .terminal: return TerminalReporter()
        case .json: return JSONReporter()
        case .html: return HTMLReporter()
        }
    }
}
