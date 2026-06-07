import Foundation

/// Renders a machine-readable JSON report.
///
/// Serialisation is straightforward (it is not scanning logic), so it is wired
/// up here; the schema may be extended as the engine matures.
public struct JSONReporter: Reporter {
    public init() {}

    public func render(_ result: ScanResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Failed to encode report\"}"
        }
        return string
    }
}
