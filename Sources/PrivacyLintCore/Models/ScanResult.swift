import Foundation

/// The outcome of running a single check (one ``Scanner``) against a project.
public struct CheckOutcome: Codable, Sendable {
    public let ruleIdentifier: String
    public let title: String
    public let passed: Bool
    public let violations: [Violation]

    public init(ruleIdentifier: String, title: String, passed: Bool, violations: [Violation]) {
        self.ruleIdentifier = ruleIdentifier
        self.title = title
        self.passed = passed
        self.violations = violations
    }
}

/// The aggregated result of a full compliance scan.
public struct ScanResult: Codable, Sendable {
    public let projectPath: String
    public let outcomes: [CheckOutcome]

    public init(projectPath: String, outcomes: [CheckOutcome]) {
        self.projectPath = projectPath
        self.outcomes = outcomes
    }

    /// Every violation across all checks.
    public var allViolations: [Violation] {
        outcomes.flatMap(\.violations)
    }

    /// True when no check reported a failure.
    public var passed: Bool {
        outcomes.allSatisfy(\.passed)
    }
}
