import Foundation
import PrivacyLintRules

/// Builds the project's dependency tree from `Package.swift` and `Podfile`, then
/// cross-references each dependency against Apple's list of SDKs that are
/// required to ship a privacy manifest.
public struct DependencyResolver: ComplianceScanner {
    public let ruleIdentifier = "third-party-sdk-manifest"
    public let title = "Third-party SDK privacy manifests"

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        // TODO: Parse dependency manifests and check against ThirdPartySDKList.required.
        throw ScannerError.notImplemented
    }
}
