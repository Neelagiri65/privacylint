import Foundation
import PrivacyLintRules
import SwiftParser
import SwiftSyntax

/// Detects calls to external AI / LLM services (OpenAI, Anthropic, Google AI,
/// Mistral, Cohere) and verifies that a user-consent surface exists somewhere
/// in the production source — a rule Apple has enforced through review since
/// November 2025.
///
/// This is PrivacyLint's launch differentiator: no existing scanner does it.
///
/// Scope (v1):
/// - **AI usage**: static URL string literals matching `AIServiceEndpoints.hosts`,
///   plus `import <pkg>` statements naming a known AI SDK.
/// - **Consent surface**: any identifier (variable, function, property, type,
///   parameter) whose camelCase / snake_case components contain BOTH an AI
///   token (`ai`, `openai`, `anthropic`, `llm`, `gpt`, `claude`, `chatgpt`)
///   AND a consent token (`consent`, `agree`, `accept`, `optin`, `permission`,
///   `allow`, `disclosure`). Or any string literal containing an AI provider
///   name AND a consent verb.
///
/// Out of scope (v1) — documented in README:
/// - Whether the consent UI is actually presented at runtime before the AI
///   call. We confirm the surface exists; we can't statically prove call
///   ordering.
/// - Runtime-constructed URLs.
/// - Localised consent strings — keyword matching is English-only.
/// - Severity is **capped at `.warning`** because static analysis cannot
///   prove a consent UI is sufficiently clear or shown to the user. False
///   positives here erode trust fastest; we prefer to flag and let the
///   developer confirm rather than fail-loud with `.error`.
public struct AIConsentDetector: ComplianceScanner {
    public let ruleIdentifier = "ai-consent"
    public let title = "AI service consent"

    /// AI consent applies wherever the app ships — every Apple platform.
    public var applicablePlatforms: Set<ApplePlatform> { Set(ApplePlatform.allCases) }

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        var aiUsages: [AIUsage] = []
        var consentFound = false

        for url in context.sourceFiles {
            let source = try String(contentsOf: url, encoding: .utf8)
            let result = analyse(source: source, file: url)
            aiUsages.append(contentsOf: result.aiUsages)
            if result.consentIndicators > 0 { consentFound = true }
        }

        // 11. No AI usage → short-circuit; we never scrutinise consent in
        //     projects that don't use AI. This also keeps PrivacyLint quiet
        //     on the vast majority of apps.
        guard !aiUsages.isEmpty else { return [] }

        // 1, 3, 4, 12. AI usage with at least one consent indicator → silent.
        if consentFound { return [] }

        // 2, 5, 6, 13. AI usage and no consent indicator → warning. Capped
        // at .warning by design — see type doc.
        let providers = Set(aiUsages.map(\.provider)).sorted().joined(separator: ", ")
        let firstUsage = aiUsages[0]
        return [
            Violation(
                ruleIdentifier: ruleIdentifier,
                severity: .warning,
                message: "Your code calls AI services (\(providers)) but PrivacyLint found no in-app consent surface (identifier or UI string mentioning AI consent / disclosure / permission). Apple has rejected apps under the Nov 2025 AI-consent guidance for missing this.",
                location: firstUsage.location,
                remediation: "Add a consent UI before the first AI call — a `.alert` / `.sheet` / `UIAlertController` titled something like \"Allow ChatGPT to summarise your messages?\" with explicit Accept / Decline buttons. Verify it appears in production source (not just tests)."
            )
        ]
    }

    // MARK: - Analysis

    struct AIUsage: Equatable {
        let provider: String
        let evidence: String  // host or package name
        let location: PrivacyLintCore.SourceLocation
    }

    struct AnalysisResult {
        var aiUsages: [AIUsage] = []
        var consentIndicators: Int = 0
    }

    /// Test-friendly entry point.
    func analyse(source: String, file: URL) -> AnalysisResult {
        let tree = Parser.parse(source: source)
        let visitor = AIConsentVisitor(file: file, tree: tree)
        visitor.walk(tree)
        return AnalysisResult(
            aiUsages: visitor.aiUsages,
            consentIndicators: visitor.consentIndicatorCount
        )
    }
}

// MARK: - Tokens

private enum AITokens {
    static let identifierTokens: Set<String> = [
        "ai", "openai", "anthropic", "llm", "gpt", "chatgpt", "claude", "gemini", "mistral", "cohere"
    ]

    static let literalProviders: Set<String> = [
        "openai", "anthropic", "chatgpt", "claude", "gemini", "mistral", "cohere", "ai", "llm"
    ]
}

private enum ConsentTokens {
    static let identifierTokens: Set<String> = [
        "consent", "agree", "agreed", "accept", "accepted", "optin", "optedin",
        "permission", "allow", "allowed", "allowance", "disclosure", "disclose", "disclosed"
    ]

    static let literalVerbs: Set<String> = [
        "consent", "allow", "accept", "agree", "decline", "share", "send your", "your data", "permission", "disclosure", "may use"
    ]
}

// MARK: - Identifier tokenisation

extension String {
    /// Split a camelCase / snake_case / kebab-case identifier into lowercased
    /// components. Splits at:
    /// - Underscore or dash.
    /// - Lowercase → Uppercase boundaries (`hasAccepted` → `has`/`Accepted`).
    /// - Acronym → Word boundaries (`AIConsent` → `AI`/`Consent`,
    ///   `IOError` → `IO`/`Error`), recognised when an uppercase letter is
    ///   followed by a lowercase letter and the previous char was also upper.
    func splitCamelSnake() -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(self)
        for i in 0..<chars.count {
            let ch = chars[i]
            if ch == "_" || ch == "-" {
                if !current.isEmpty { result.append(current.lowercased()) }
                current = ""
                continue
            }
            if ch.isUppercase {
                let prev: Character? = i > 0 ? chars[i - 1] : nil
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let camelBoundary = prev?.isLowercase == true
                let acronymToWord = prev?.isUppercase == true && next?.isLowercase == true
                if (camelBoundary || acronymToWord) && !current.isEmpty {
                    result.append(current.lowercased())
                    current = ""
                }
            }
            current.append(ch)
        }
        if !current.isEmpty { result.append(current.lowercased()) }
        return result
    }
}

private func identifierMatchesConsent(_ identifier: String) -> Bool {
    let parts = identifier.splitCamelSnake()
    let hasAI = parts.contains { AITokens.identifierTokens.contains($0) }
    let hasConsent = parts.contains { ConsentTokens.identifierTokens.contains($0) }
    return hasAI && hasConsent
}

private func literalMatchesConsent(_ literal: String) -> Bool {
    let lower = literal.lowercased()
    let hasProvider = AITokens.literalProviders.contains { lower.contains($0) }
    let hasVerb = ConsentTokens.literalVerbs.contains { lower.contains($0) }
    return hasProvider && hasVerb
}

// MARK: - Visitor

private final class AIConsentVisitor: SyntaxVisitor {
    private let file: URL
    private let converter: SourceLocationConverter
    private let knownHosts: [String: String]  // host → provider name
    private let knownPackages: [String: String] // normalised package → provider

    var aiUsages: [AIConsentDetector.AIUsage] = []
    var consentIndicatorCount = 0

    init(file: URL, tree: SourceFileSyntax) {
        self.file = file
        self.converter = SourceLocationConverter(fileName: file.path, tree: tree)
        var hosts: [String: String] = [:]
        var packages: [String: String] = [:]
        for service in AIServiceEndpoints.known {
            for host in service.hosts { hosts[host.lowercased()] = service.provider }
            for pkg in service.packages {
                let normalised = pkg.split(separator: "/").last.map(String.init) ?? pkg
                packages[normalised.lowercased()] = service.provider
            }
        }
        self.knownHosts = hosts
        self.knownPackages = packages
        super.init(viewMode: .sourceAccurate)
    }

    // String literals: AI host URL OR consent-UI copy.
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Only fully-static literals — interpolation is out of scope (documented).
        var literal = ""
        for segment in node.segments {
            guard let strSeg = segment.as(StringSegmentSyntax.self) else {
                return .visitChildren
            }
            literal += strSeg.content.text
        }
        guard !literal.isEmpty else { return .visitChildren }

        if let host = extractHost(from: literal),
           let provider = knownHosts[host.lowercased()] {
            let loc = node.startLocation(converter: converter)
            aiUsages.append(
                AIConsentDetector.AIUsage(
                    provider: provider,
                    evidence: host,
                    location: PrivacyLintCore.SourceLocation(file: file.path, line: loc.line, column: loc.column)
                )
            )
        }

        if literalMatchesConsent(literal) {
            consentIndicatorCount += 1
        }
        return .visitChildren
    }

    // Imports — `import OpenAI`, `import Anthropic`.
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.map(\.name.text).joined(separator: ".")
        let normalised = moduleName.lowercased()
        if let provider = knownPackages[normalised] {
            let loc = node.startLocation(converter: converter)
            aiUsages.append(
                AIConsentDetector.AIUsage(
                    provider: provider,
                    evidence: "import \(moduleName)",
                    location: PrivacyLintCore.SourceLocation(file: file.path, line: loc.line, column: loc.column)
                )
            )
        }
        return .visitChildren
    }

    // Identifiers in declarations (variable, function, parameter, type names).
    // Walking IdentifierPatternSyntax/FunctionDeclSyntax/etc. separately is
    // simpler than scanning every TokenSyntax — fewer false positives, faster.
    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        check(identifier: node.identifier.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        check(identifier: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        check(identifier: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        check(identifier: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        check(identifier: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
        check(identifier: node.name.text)
        return .visitChildren
    }

    private func check(identifier: String) {
        if identifierMatchesConsent(identifier) {
            consentIndicatorCount += 1
        }
    }

    private func extractHost(from literal: String) -> String? {
        if let comps = URLComponents(string: literal), let host = comps.host {
            return host
        }
        let trimmed = literal.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(" ") { return nil }
        if !trimmed.contains(".") { return nil }
        if let comps = URLComponents(string: "https://" + trimmed), let host = comps.host {
            return host
        }
        return nil
    }
}
