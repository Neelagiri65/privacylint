import Foundation
import PrivacyLintRules

/// Scans source code for use of Apple's Required Reason APIs and verifies that
/// each use is backed by a declared reason in the privacy manifest.
///
/// The real implementation performs AST-level analysis with SwiftSyntax so that
/// it can distinguish production code from comments, test targets and dead code.
public struct RequiredReasonAPIScanner: ComplianceScanner {
    public let ruleIdentifier = "required-reason-api"
    public let title = "Required Reason API usage"

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        // TODO: AST-level scan using SwiftSyntax against RequiredReasonAPIs.all.
        throw ScannerError.notImplemented
    }
}
