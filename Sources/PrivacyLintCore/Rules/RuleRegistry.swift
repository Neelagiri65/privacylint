import Foundation

/// The central catalogue of all compliance checks.
///
/// New scanners are registered here so the CLI and tests share one source of
/// truth for which rules run.
public struct RuleRegistry {
    public let scanners: [any ComplianceScanner]

    public init(scanners: [any ComplianceScanner] = RuleRegistry.allScanners) {
        self.scanners = scanners
    }

    /// Every scanner shipped with PrivacyLint, in execution order.
    public static var allScanners: [any ComplianceScanner] {
        [
            RequiredReasonAPIScanner(),
            DependencyResolver(),
            PrivacyManifestValidator(),
            TrackingDomainChecker(),
            AIConsentDetector()
        ]
    }

    /// Run every registered scanner against the context and aggregate the
    /// result. All status bookkeeping (platform skipping, not-implemented
    /// fallback, thrown errors) is delegated to `ComplianceScanner.makeOutcome`
    /// so the JSON output lists *every* registered check with its true status.
    public func run(_ context: ScanContext) -> ScanResult {
        let outcomes = scanners.map { $0.makeOutcome(context) }
        let detected = Array(context.platforms).sorted { $0.rawValue < $1.rawValue }
        return ScanResult(
            projectPath: context.projectPath.path,
            detectedPlatforms: detected,
            outcomes: outcomes
        )
    }
}
