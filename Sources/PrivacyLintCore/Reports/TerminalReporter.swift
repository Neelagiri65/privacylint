import Foundation

/// Renders a coloured, hierarchical, terminal-friendly report.
///
/// Layout (one block per scanner):
///
///     PrivacyLint v0.0.1  ·  /path/to/project
///     Platforms: iOS, macOS
///
///     [required-reason-api] Required Reason API usage
///     ✓ passed
///
///     [privacy-manifest-validation] Privacy manifest validation
///     ✗ failed · 1 error
///
///       error  Sources/App/Loader.swift:5:13
///           `UserDefaults` triggers ... ITMS-91053
///           fix-it: Declare one of [CA92.1, ...] in PrivacyInfo.xcprivacy.
///
///     Summary
///       ✗ 1 failed   ✓ 4 passed   ·   errors: 1   warnings: 0
///       Status: FAILED
///
/// ANSI colour is on by default; the CLI disables it when stdout is not a TTY
/// or `--no-color` is passed.
public struct TerminalReporter: Reporter {
    private let useColour: Bool
    private let version: String

    public init(useColour: Bool = true, version: String = "0.0.1") {
        self.useColour = useColour
        self.version = version
    }

    public func render(_ result: ScanResult) -> String {
        var out: [String] = []
        out.append(header(for: result))
        out.append("")
        for outcome in result.outcomes {
            out.append(scannerBlock(outcome, projectPath: result.projectPath))
            out.append("")
        }
        out.append(contentsOf: summary(for: result))
        return out.joined(separator: "\n")
    }

    // MARK: - Sections

    private func header(for result: ScanResult) -> String {
        let title = bold("PrivacyLint v\(version)")
        let path = grey(result.projectPath)
        let head = "\(title)  ·  \(path)"
        let platforms: String
        if result.detectedPlatforms.isEmpty {
            platforms = grey("Platforms: not detected (every scanner applies)")
        } else {
            let list = result.detectedPlatforms.map(\.rawValue).joined(separator: ", ")
            platforms = grey("Platforms: ") + list
        }
        return "\(head)\n\(platforms)"
    }

    private func scannerBlock(_ outcome: CheckOutcome, projectPath: String) -> String {
        var lines: [String] = []
        let id = "[\(outcome.ruleIdentifier)]"
        lines.append("\(bold(id)) \(outcome.title)")
        lines.append(statusLine(outcome))

        for violation in outcome.violations {
            lines.append("")
            lines.append(violationLines(violation, projectPath: projectPath))
        }
        return lines.joined(separator: "\n")
    }

    private func statusLine(_ outcome: CheckOutcome) -> String {
        switch outcome.status {
        case .passed where outcome.violations.isEmpty:
            return green("✓ passed")
        case .passed:
            let warnings = outcome.violations.filter { $0.severity == .warning }.count
            return green("✓ passed") + grey(" · \(warnings) warning\(warnings == 1 ? "" : "s")")
        case .failed:
            let errors = outcome.violations.filter { $0.severity == .error }.count
            let warnings = outcome.violations.filter { $0.severity == .warning }.count
            var bits: [String] = []
            if errors > 0 { bits.append("\(errors) error\(errors == 1 ? "" : "s")") }
            if warnings > 0 { bits.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
            return red("✗ failed") + grey(" · " + bits.joined(separator: ", "))
        case .skippedForPlatform:
            let applies = outcome.applicablePlatforms.map(\.rawValue).joined(separator: ", ")
            return grey("— skipped · applies to: \(applies)")
        case .notImplemented:
            return grey("— not implemented")
        }
    }

    private func violationLines(_ v: Violation, projectPath: String) -> String {
        var lines: [String] = []
        let badge: String
        switch v.severity {
        case .error:   badge = red("  error")
        case .warning: badge = yellow("warning")
        case .info:    badge = blue("   info")
        }

        if let loc = v.location {
            let relative = relativePath(loc.file, base: projectPath)
            lines.append("  \(badge)  \(relative):\(loc.line):\(loc.column)")
        } else {
            lines.append("  \(badge)  (no location)")
        }
        for line in wrap(v.message, indent: 11) { lines.append(line) }
        if let remediation = v.remediation, !remediation.isEmpty {
            let fixLines = wrap("fix-it: " + remediation, indent: 11)
            for line in fixLines { lines.append(grey(line)) }
        }
        return lines.joined(separator: "\n")
    }

    private func summary(for result: ScanResult) -> [String] {
        var lines: [String] = []
        lines.append(bold("Summary"))

        let failed = result.outcomes.filter { $0.status == .failed }.count
        let passed = result.outcomes.filter { $0.status == .passed }.count
        let skipped = result.outcomes.filter { $0.status == .skippedForPlatform }.count
        let notImpl = result.outcomes.filter { $0.status == .notImplemented }.count

        let totalErrors = result.allViolations.filter { $0.severity == .error }.count
        let totalWarnings = result.allViolations.filter { $0.severity == .warning }.count

        var bits: [String] = []
        if failed > 0 { bits.append(red("✗ \(failed) failed")) }
        if passed > 0 { bits.append(green("✓ \(passed) passed")) }
        if skipped > 0 { bits.append(grey("— \(skipped) skipped")) }
        if notImpl > 0 { bits.append(grey("— \(notImpl) not implemented")) }
        lines.append("  " + bits.joined(separator: "   ") +
                     grey("   ·   errors: \(totalErrors)   warnings: \(totalWarnings)"))

        let status: String
        if result.passed {
            status = green("Status: PASSED")
        } else {
            status = red("Status: FAILED") + grey(" — App Review will block the next submission until the errors are fixed.")
        }
        lines.append("  \(status)")
        return lines
    }

    // MARK: - Path

    private func relativePath(_ absolute: String, base: String) -> String {
        guard !base.isEmpty else { return absolute }
        // Compare canonicalised pathComponents so /tmp ↔ /private/tmp (a
        // macOS symlink) doesn't defeat the strip. Same defence
        // ProjectDiscovery uses on the way in.
        let baseComponents = URL(fileURLWithPath: base)
            .resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let absComponents = URL(fileURLWithPath: absolute)
            .resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard absComponents.starts(with: baseComponents) else { return absolute }
        let relative = absComponents.dropFirst(baseComponents.count).joined(separator: "/")
        return relative.isEmpty ? absolute : relative
    }

    // MARK: - Wrap

    /// Word-wrap a paragraph at ~80 columns with a constant indent on every
    /// line. Preserves long words whole (URLs, identifiers).
    private func wrap(_ text: String, indent: Int) -> [String] {
        let prefix = String(repeating: " ", count: indent)
        let width = max(20, 80 - indent)
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= width {
                current += " " + w
            } else {
                lines.append(prefix + current)
                current = w
            }
        }
        if !current.isEmpty { lines.append(prefix + current) }
        return lines
    }

    // MARK: - ANSI

    private func bold(_ s: String) -> String { useColour ? "\u{001B}[1m\(s)\u{001B}[0m" : s }
    private func grey(_ s: String) -> String { useColour ? "\u{001B}[90m\(s)\u{001B}[0m" : s }
    private func red(_ s: String) -> String { useColour ? "\u{001B}[31m\(s)\u{001B}[0m" : s }
    private func green(_ s: String) -> String { useColour ? "\u{001B}[32m\(s)\u{001B}[0m" : s }
    private func yellow(_ s: String) -> String { useColour ? "\u{001B}[33m\(s)\u{001B}[0m" : s }
    private func blue(_ s: String) -> String { useColour ? "\u{001B}[34m\(s)\u{001B}[0m" : s }
}
