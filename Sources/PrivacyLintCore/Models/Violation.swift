import Foundation

/// The severity of a compliance finding.
public enum Severity: String, Codable, Sendable, CaseIterable {
    /// A blocking issue that will likely cause an App Store rejection.
    case error
    /// A probable issue that should be reviewed before submission.
    case warning
    /// Informational context that does not block submission.
    case info
}

/// A precise location within a source file.
public struct SourceLocation: Codable, Sendable, Equatable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

/// A single compliance finding produced by a ``Scanner``.
public struct Violation: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// The identifier of the rule that produced this violation.
    public let ruleIdentifier: String
    public let severity: Severity
    /// A human-readable description of the problem (British English).
    public let message: String
    /// Where the problem was found, if applicable.
    public let location: SourceLocation?
    /// Guidance on how to resolve the violation.
    public let remediation: String?

    public init(
        id: UUID = UUID(),
        ruleIdentifier: String,
        severity: Severity,
        message: String,
        location: SourceLocation? = nil,
        remediation: String? = nil
    ) {
        self.id = id
        self.ruleIdentifier = ruleIdentifier
        self.severity = severity
        self.message = message
        self.location = location
        self.remediation = remediation
    }
}
