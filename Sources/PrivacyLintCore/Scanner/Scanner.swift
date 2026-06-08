import Foundation

/// The shared context handed to every ``ComplianceScanner`` for a single run.
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
    /// The Apple platforms this project targets. Empty means "unknown — assume
    /// every platform applies." Conservative on purpose: under-scanning is
    /// worse than over-scanning since false positives are dismissable and
    /// missed checks become App Store rejections.
    public let platforms: Set<ApplePlatform>

    public init(
        projectPath: URL,
        sourceFiles: [URL] = [],
        testFiles: [URL] = [],
        objcFiles: [URL] = [],
        dependencyManifests: [URL] = [],
        privacyManifests: [URL] = [],
        platforms: Set<ApplePlatform> = []
    ) {
        self.projectPath = projectPath
        self.sourceFiles = sourceFiles
        self.testFiles = testFiles
        self.objcFiles = objcFiles
        self.dependencyManifests = dependencyManifests
        self.privacyManifests = privacyManifests
        self.platforms = platforms
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
    /// The platforms this check applies to. Default: every platform — most
    /// privacy rules (tracking, collected data, manifest presence) apply
    /// across the board. Scanners with narrower scope (e.g. Required-Reason
    /// API which exempts macOS) override this.
    var applicablePlatforms: Set<ApplePlatform> { get }
    /// Run the check and return any violations found.
    func scan(_ context: ScanContext) throws -> [Violation]
}

public extension ComplianceScanner {
    var applicablePlatforms: Set<ApplePlatform> { Set(ApplePlatform.allCases) }

    /// Whether this scanner has any relevance to the project's detected
    /// platforms. Empty `context.platforms` means "unknown → assume all"
    /// and the scanner runs.
    func isApplicable(to context: ScanContext) -> Bool {
        guard !context.platforms.isEmpty else { return true }
        return !applicablePlatforms.isDisjoint(with: context.platforms)
    }

    /// Convenience wrapper that packages this scanner's findings into a
    /// ``CheckOutcome``, honouring platform-applicability and the
    /// `notImplemented` opt-out.
    func makeOutcome(_ context: ScanContext) -> CheckOutcome {
        let applicableList = Array(applicablePlatforms).sorted { $0.rawValue < $1.rawValue }
        guard isApplicable(to: context) else {
            return CheckOutcome(
                ruleIdentifier: ruleIdentifier,
                title: title,
                status: .skippedForPlatform,
                applicablePlatforms: applicableList
            )
        }
        do {
            let violations = try scan(context)
            let blocking = violations.contains { $0.severity == .error }
            return CheckOutcome(
                ruleIdentifier: ruleIdentifier,
                title: title,
                status: blocking ? .failed : .passed,
                applicablePlatforms: applicableList,
                violations: violations
            )
        } catch ScannerError.notImplemented {
            return CheckOutcome(
                ruleIdentifier: ruleIdentifier,
                title: title,
                status: .notImplemented,
                applicablePlatforms: applicableList
            )
        } catch {
            return CheckOutcome(
                ruleIdentifier: ruleIdentifier,
                title: title,
                status: .failed,
                applicablePlatforms: applicableList,
                violations: [
                    Violation(
                        ruleIdentifier: ruleIdentifier,
                        severity: .error,
                        message: "The check failed to run: \(error.localizedDescription)"
                    )
                ]
            )
        }
    }
}

/// Errors thrown by scanners.
public enum ScannerError: Error, Equatable {
    /// The scanner's analysis logic has not been implemented yet.
    case notImplemented
}
