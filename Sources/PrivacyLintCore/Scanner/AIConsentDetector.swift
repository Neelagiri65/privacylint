import Foundation
import PrivacyLintRules

/// Detects calls to external AI/LLM services (OpenAI, Anthropic, Google AI, etc.)
/// and verifies the presence of an AI consent modal — required by Apple since
/// November 2025.
///
/// This is PrivacyLint's headline differentiator: no existing competitor checks
/// for AI consent compliance.
public struct AIConsentDetector: ComplianceScanner {
    public let ruleIdentifier = "ai-consent"
    public let title = "AI service consent"

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        // TODO: Detect AI endpoint usage against AIServiceEndpoints.known and
        // verify a consent modal is presented before the first call.
        throw ScannerError.notImplemented
    }
}
