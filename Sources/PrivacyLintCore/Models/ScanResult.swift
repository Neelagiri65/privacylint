import Foundation

/// What happened when a single check ran (or didn't).
///
/// Honesty over invisibility — a `notImplemented` scanner used to silently
/// vanish from the output, making the report look more complete than it
/// was. With this enum, the JSON now lists every check and its status.
public enum CheckStatus: String, Codable, Sendable {
    /// The check ran and found no blocking violations.
    case passed
    /// The check ran and found at least one `.error` violation.
    case failed
    /// The check did not run because none of the project's target platforms
    /// require it. Example: `required-reason-api` against a macOS-only
    /// project — macOS is exempt, so the scanner is correctly skipped.
    case skippedForPlatform
    /// The check is scaffolded but its scanner logic is not yet built.
    case notImplemented
}

/// The outcome of running a single check (one ``ComplianceScanner``) against
/// a project.
public struct CheckOutcome: Codable, Sendable {
    public let ruleIdentifier: String
    public let title: String
    public let status: CheckStatus
    /// The platforms this check applies to (from the scanner's own
    /// `applicablePlatforms`). Surfaced so the report can render
    /// "skipped — not required on macOS" with the relevant platforms named.
    public let applicablePlatforms: [ApplePlatform]
    public let violations: [Violation]

    public init(
        ruleIdentifier: String,
        title: String,
        status: CheckStatus,
        applicablePlatforms: [ApplePlatform] = [],
        violations: [Violation] = []
    ) {
        self.ruleIdentifier = ruleIdentifier
        self.title = title
        self.status = status
        self.applicablePlatforms = applicablePlatforms
        self.violations = violations
    }

    /// True unless the check actively failed. Skipped and not-implemented
    /// outcomes are treated as non-failures — they're informational, not
    /// blocking. The terminal reporter should show their status text so
    /// users see them, but they don't fail a CI gate.
    public var passed: Bool { status != .failed }
}

/// The aggregated result of a full compliance scan.
public struct ScanResult: Codable, Sendable {
    public let projectPath: String
    /// The platforms PrivacyLint detected for this project (from
    /// `Package.swift`, `.xcodeproj`, or — when detection fails — empty,
    /// meaning "unknown; assume all").
    public let detectedPlatforms: [ApplePlatform]
    public let outcomes: [CheckOutcome]

    public init(
        projectPath: String,
        detectedPlatforms: [ApplePlatform] = [],
        outcomes: [CheckOutcome]
    ) {
        self.projectPath = projectPath
        self.detectedPlatforms = detectedPlatforms
        self.outcomes = outcomes
    }

    public var allViolations: [Violation] { outcomes.flatMap(\.violations) }

    /// True when no check actively failed.
    public var passed: Bool { outcomes.allSatisfy(\.passed) }
}
