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

    /// Run every registered scanner against the context and aggregate the result.
    ///
    /// Scanners that throw ``ScannerError/notImplemented`` are skipped during the
    /// scaffold phase; once the engine is built this will surface real outcomes.
    public func run(_ context: ScanContext) -> ScanResult {
        var outcomes: [CheckOutcome] = []
        for scanner in scanners {
            do {
                outcomes.append(try scanner.makeOutcome(context))
            } catch ScannerError.notImplemented {
                continue
            } catch {
                outcomes.append(
                    CheckOutcome(
                        ruleIdentifier: scanner.ruleIdentifier,
                        title: scanner.title,
                        passed: false,
                        violations: [
                            Violation(
                                ruleIdentifier: scanner.ruleIdentifier,
                                severity: .error,
                                message: "The check failed to run: \(error.localizedDescription)"
                            )
                        ]
                    )
                )
            }
        }
        return ScanResult(projectPath: context.projectPath.path, outcomes: outcomes)
    }
}
