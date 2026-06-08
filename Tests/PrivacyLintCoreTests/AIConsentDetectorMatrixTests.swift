import Foundation
import Testing
@testable import PrivacyLintCore
import PrivacyLintRules

/// The architectural gate for AIConsentDetector — PrivacyLint's launch
/// differentiator. Static analysis can't prove a consent UI is shown to
/// the user before an AI call; what we CAN prove is the presence (or
/// absence) of any consent surface in production source.
///
/// Severity is capped at .warning by design: false positives here erode
/// trust fastest, so we prefer to flag-and-explain rather than fail-loud.
///
/// Matrix — each row maps to at least one test.
///
/// | #  | Scenario                                                         | Expected outcome                                |
/// | -- | ---------------------------------------------------------------- | ----------------------------------------------- |
/// | 1  | AI URL + identifier `hasAcceptedAIConsent`                       | passed                                          |
/// | 2  | AI URL, no consent signal anywhere                               | .warning                                        |
/// | 3  | AI URL + function `presentLLMConsent`                            | passed                                          |
/// | 4  | AI URL + literal "Allow ChatGPT to summarise…"                   | passed                                          |
/// | 5  | Anthropic URL, no consent                                        | .warning                                        |
/// | 6  | `import OpenAI` (no URL); no consent                             | .warning (package counts as AI usage)           |
/// | 7  | AI URL in comment only                                           | not flagged (Trivia)                            |
/// | 8  | AI URL in test target                                            | not flagged (ScanContext.testFiles excluded)    |
/// | 9  | AI URL in string interpolation                                   | not detected (v1 limit)                         |
/// | 10 | applicablePlatforms = all                                        | runs on macOS-only                              |
/// | 11 | No AI usage                                                      | silent (short-circuit)                          |
/// | 12 | Multiple providers + one consent surface                         | passed                                          |
/// | 13 | Consent only in test files (separate context.testFiles)          | .warning                                        |
/// | 14 | `pairSelected` identifier (false-positive guard, no AI token)    | not consent signal                              |
/// | 15 | `aiAvailable` identifier (false-positive guard, no consent token)| not consent signal                              |
@Suite("AIConsentDetector — architectural gate")
struct AIConsentDetectorMatrixTests {

    @Test func appliesToEveryPlatformIncludingMacOS() {
        #expect(AIConsentDetector().applicablePlatforms == Set(ApplePlatform.allCases))
    }

    // MARK: - String tokenisation helpers

    @Test func splitsCamelCase() {
        #expect("hasAcceptedAIConsent".splitCamelSnake() == ["has", "accepted", "ai", "consent"])
        #expect("presentLLMConsent".splitCamelSnake() == ["present", "llm", "consent"])
        #expect("openAIDisclosure".splitCamelSnake() == ["open", "ai", "disclosure"])
    }

    @Test func splitsSnakeCase() {
        #expect("has_accepted_ai_consent".splitCamelSnake() == ["has", "accepted", "ai", "consent"])
    }

    // MARK: - Analyser unit coverage

    private let checker = AIConsentDetector()
    private let tmpFile = URL(fileURLWithPath: "/tmp/Sample.swift")

    @Test func findsAIURL() {
        let source = """
        let url = URL(string: "https://api.openai.com/v1/chat")
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.aiUsages.count == 1)
        #expect(r.aiUsages.first?.provider == "OpenAI")
    }

    @Test func findsAnthropicURL() {
        let source = """
        let url = "https://api.anthropic.com/v1/messages"
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.aiUsages.first?.provider == "Anthropic")
    }

    @Test func findsImportedSDK() {
        let source = """
        import Foundation
        import OpenAI
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.aiUsages.contains { $0.provider == "OpenAI" })
    }

    @Test func ignoresAIURLInComment() {
        let source = """
        // We used to call https://api.openai.com/v1/chat
        let x = 1
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.aiUsages.isEmpty)
    }

    @Test func ignoresInterpolatedAIURL() {
        let source = #"""
        let host = "api.openai.com"
        let url = "https://\(host)/v1/chat"
        """#
        let r = checker.analyse(source: source, file: tmpFile)
        // The bare hostname literal IS detected (it's a static reference).
        // The interpolated URL is not (dynamic, out of v1 scope).
        #expect(r.aiUsages.count == 1)
        #expect(r.aiUsages.first?.provider == "OpenAI")
    }

    @Test func consentIdentifierIsRecognised() {
        let source = """
        var hasAcceptedAIConsent: Bool = false
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.consentIndicators > 0)
    }

    @Test func consentFunctionNameIsRecognised() {
        let source = """
        func presentLLMConsent() {}
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.consentIndicators > 0)
    }

    @Test func consentLiteralIsRecognised() {
        let source = #"""
        let title = "Allow ChatGPT to summarise your messages?"
        """#
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.consentIndicators > 0)
    }

    @Test func falsePositiveGuard_pairSelectedIsNotConsent() {
        // Has neither AI nor consent token → not a signal.
        let source = """
        var pairSelected: Bool = false
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.consentIndicators == 0)
    }

    @Test func falsePositiveGuard_aiAvailableIsNotConsent() {
        // Has AI token but no consent token → not a signal.
        let source = """
        var aiAvailable: Bool = true
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.consentIndicators == 0)
    }

    @Test func falsePositiveGuard_consentWithoutAIIsNotSignal() {
        // Has consent token but no AI token → not a signal (this could be
        // ATT consent, GDPR consent, anything else).
        let source = """
        var hasAcceptedTrackingConsent: Bool = false
        """
        let r = checker.analyse(source: source, file: tmpFile)
        #expect(r.consentIndicators == 0)
    }

    // MARK: - End-to-end (scan)

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-aic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSource(_ text: String, in dir: URL, named: String = "App.swift") throws -> URL {
        let url = dir.appendingPathComponent(named)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func scenario1_aiUsageWithConsentPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        var hasAcceptedAIConsent = false
        let url = URL(string: "https://api.openai.com/v1/chat")
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], platforms: [.iOS])
        let violations = try AIConsentDetector().scan(context)
        #expect(violations.isEmpty, "Unexpected: \(violations.map(\.message))")
    }

    @Test func scenario2_aiUsageNoConsentWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        let url = URL(string: "https://api.openai.com/v1/chat")
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], platforms: [.iOS])
        let violations = try AIConsentDetector().scan(context)
        #expect(violations.count == 1)
        let v = try #require(violations.first)
        #expect(v.severity == .warning) // never .error — false-positive cost too high
        #expect(v.message.contains("OpenAI"))
        #expect(v.message.contains("AI-consent"))
    }

    @Test func scenario11_noAIUsageIsSilent() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        let url = URL(string: "https://api.mybackend.io/v1/widgets")
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], platforms: [.iOS])
        let violations = try AIConsentDetector().scan(context)
        #expect(violations.isEmpty)
    }

    @Test func scenario12_multipleProvidersOneConsentPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        var hasAcceptedAIConsent = false
        let a = URL(string: "https://api.openai.com/v1/chat")
        let b = URL(string: "https://api.anthropic.com/v1/messages")
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], platforms: [.iOS])
        let violations = try AIConsentDetector().scan(context)
        #expect(violations.isEmpty, "Unexpected: \(violations.map(\.message))")
    }

    @Test func scenario13_consentOnlyInTestsStillWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Production source: AI URL, no consent.
        let prod = try writeSource("""
        import Foundation
        let url = URL(string: "https://api.openai.com/v1/chat")
        """, in: dir, named: "App.swift")
        // Test source: has consent indicator. But testFiles is NOT scanned.
        let test = try writeSource("""
        import XCTest
        var hasAcceptedAIConsent = false
        """, in: dir, named: "AppTests.swift")
        let context = ScanContext(
            projectPath: dir,
            sourceFiles: [prod],
            testFiles: [test],
            platforms: [.iOS]
        )
        let violations = try AIConsentDetector().scan(context)
        #expect(violations.count == 1)
        #expect(violations.first?.severity == .warning)
    }

    @Test func scenario10_macOSOnlyProjectStillRuns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        let url = URL(string: "https://api.openai.com/v1/chat")
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], platforms: [.macOS])
        let result = RuleRegistry().run(context)
        let aic = try #require(result.outcomes.first { $0.ruleIdentifier == "ai-consent" })
        // Not skipped — applicablePlatforms is all.
        #expect(aic.status == .passed) // warnings don't fail
        #expect(aic.violations.first?.severity == .warning)
    }
}
