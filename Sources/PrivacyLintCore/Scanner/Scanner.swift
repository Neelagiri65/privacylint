import Foundation

/// The shared context handed to every ``Scanner`` for a single run.
///
/// The discovery logic that populates the file lists is implemented in a later
/// step; this type defines the contract the scanners depend on.
public struct ScanContext: Sendable {
    /// The root of the project being scanned.
    public let projectPath: URL
    /// Swift source files in production targets.
    public let sourceFiles: [URL]
    /// Swift source files in test targets (convention-based: directories matching `*Tests`).
    public let testFiles: [URL]
    /// Objective-C source files (`.m`, `.h`). Collected but not AST-parsed in v1.
    public let objcFiles: [URL]
    /// `Package.swift` and `Podfile` manifests discovered in the project.
    public let dependencyManifests: [URL]
    /// `PrivacyInfo.xcprivacy` files discovered in the project.
    public let privacyManifests: [URL]

    public init(
        projectPath: URL,
        sourceFiles: [URL] = [],
        testFiles: [URL] = [],
        objcFiles: [URL] = [],
        dependencyManifests: [URL] = [],
        privacyManifests: [URL] = []
    ) {
        self.projectPath = projectPath
        self.sourceFiles = sourceFiles
        self.testFiles = testFiles
        self.objcFiles = objcFiles
        self.dependencyManifests = dependencyManifests
        self.privacyManifests = privacyManifests
    }
}

/// A single, independently testable compliance check.
///
/// Named `ComplianceScanner` to avoid colliding with `Foundation.Scanner`.
public protocol ComplianceScanner: Sendable {
    /// A stable identifier for the rule, e.g. `"required-reason-api"`.
    var ruleIdentifier: String { get }
    /// A short, human-readable title (British English).
    var title: String { get }
    /// Run the check and return any violations found.
    func scan(_ context: ScanContext) throws -> [Violation]
}

public extension ComplianceScanner {
    /// Convenience wrapper that packages this scanner's findings into a ``CheckOutcome``.
    func makeOutcome(_ context: ScanContext) throws -> CheckOutcome {
        let violations = try scan(context)
        let blocking = violations.contains { $0.severity == .error }
        return CheckOutcome(
            ruleIdentifier: ruleIdentifier,
            title: title,
            passed: !blocking,
            violations: violations
        )
    }
}

/// Errors thrown by scanners.
public enum ScannerError: Error, Equatable {
    /// The scanner's analysis logic has not been implemented yet.
    case notImplemented
}
