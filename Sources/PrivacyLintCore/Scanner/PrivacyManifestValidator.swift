import Foundation

/// Validates existing `PrivacyInfo.xcprivacy` files: parses each manifest and
/// checks that the declared API reasons and tracking flags are internally
/// consistent and match how the code actually uses those APIs.
public struct PrivacyManifestValidator: ComplianceScanner {
    public let ruleIdentifier = "privacy-manifest-validation"
    public let title = "Privacy manifest validation"

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        // TODO: Parse PrivacyInfo.xcprivacy into PrivacyManifest and reconcile
        // declared reasons against detected API usage.
        throw ScannerError.notImplemented
    }
}
