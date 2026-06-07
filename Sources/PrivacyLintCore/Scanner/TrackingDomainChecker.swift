import Foundation

/// Detects network endpoints used by the app and flags any tracking domains
/// that are missing from the `NSPrivacyTrackingDomains` declaration.
public struct TrackingDomainChecker: ComplianceScanner {
    public let ruleIdentifier = "tracking-domain-declaration"
    public let title = "Tracking domain declarations"

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        // TODO: Detect outbound domains and reconcile against declared tracking domains.
        throw ScannerError.notImplemented
    }
}
