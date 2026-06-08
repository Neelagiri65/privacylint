import Foundation
import PrivacyLintRules
import SwiftParser
import SwiftSyntax

/// Scans Swift source for use of Apple's Required Reason APIs.
///
/// AST-level via SwiftSyntax so comments, doc-comments and string literals do
/// not produce false positives — the failure mode of every existing grep-based
/// tool. Test targets are skipped at the `ScanContext` level.
///
/// Scope (v1): production Swift only. Objective-C, type resolution and macro
/// expansion are out of scope (see README — Known limitations).
public struct RequiredReasonAPIScanner: ComplianceScanner {
    public let ruleIdentifier = "required-reason-api"
    public let title = "Required Reason API usage"

    /// macOS is exempt from Required-Reason API declarations (Apple, Privacy
    /// manifest files). Running this scanner on a macOS-only project would
    /// generate the same false positives that plague every grep-based tool —
    /// so we don't run it there.
    public var applicablePlatforms: Set<ApplePlatform> {
        Set(ApplePlatform.allCases.filter { $0.requiresRequiredReasonAPI })
    }

    private let rules: [RequiredReasonAPI]

    public init(rules: [RequiredReasonAPI] = RequiredReasonAPIs.all) {
        self.rules = rules
    }

    public func scan(_ context: ScanContext) throws -> [Violation] {
        var violations: [Violation] = []
        for url in context.sourceFiles {
            let source = try String(contentsOf: url, encoding: .utf8)
            violations.append(contentsOf: scanSource(source, file: url))
        }
        return violations
    }

    /// Test-friendly entry point. Skips IO so unit tests can feed a string.
    func scanSource(_ source: String, file: URL) -> [Violation] {
        let tree = Parser.parse(source: source)
        let visitor = RequiredReasonVisitor(
            file: file,
            tree: tree,
            rules: rules,
            ruleIdentifier: ruleIdentifier
        )
        visitor.walk(tree)
        return visitor.violations
    }
}

/// Index that maps a triggering symbol to its rule, so the visitor's hot path
/// is a dictionary lookup instead of a nested for-loop.
private struct RuleIndex {
    let bySymbol: [String: RequiredReasonAPI]

    init(_ rules: [RequiredReasonAPI]) {
        var map: [String: RequiredReasonAPI] = [:]
        for rule in rules {
            for symbol in rule.triggeringSymbols {
                map[symbol] = rule
            }
        }
        self.bySymbol = map
    }
}

private final class RequiredReasonVisitor: SyntaxVisitor {
    private let file: URL
    private let converter: SourceLocationConverter
    private let index: RuleIndex
    private let ruleIdentifier: String
    var violations: [Violation] = []

    init(
        file: URL,
        tree: SourceFileSyntax,
        rules: [RequiredReasonAPI],
        ruleIdentifier: String
    ) {
        self.file = file
        self.converter = SourceLocationConverter(fileName: file.path, tree: tree)
        self.index = RuleIndex(rules)
        self.ruleIdentifier = ruleIdentifier
        super.init(viewMode: .sourceAccurate)
    }

    // The rightmost member of a member-access expression. Catches:
    //   file.modificationDate            → declName = "modificationDate"
    //   ProcessInfo.processInfo.uptime   → declName = "uptime"
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.text
        if let rule = index.bySymbol[name] {
            emit(rule: rule, symbol: name, at: Syntax(node.declName))
        }
        return .visitChildren
    }

    // Bare references: `UserDefaults`, `UserDefaults()`, or the BASE of a
    // member access (`UserDefaults` in `UserDefaults.standard`). Skip the
    // case where this DeclRef is the rightmost member of a parent
    // MemberAccess — that path is handled above and we don't want to
    // double-count.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if let parent = node.parent?.as(MemberAccessExprSyntax.self),
           parent.declName.id == node.id {
            return .visitChildren
        }
        let name = node.baseName.text
        if let rule = index.bySymbol[name] {
            emit(rule: rule, symbol: name, at: Syntax(node))
        }
        return .visitChildren
    }

    private func emit(rule: RequiredReasonAPI, symbol: String, at node: Syntax) {
        let loc = node.startLocation(converter: converter)
        let reasons = rule.approvedReasons.joined(separator: ", ")
        violations.append(
            Violation(
                ruleIdentifier: ruleIdentifier,
                severity: .warning,
                message: "Use of `\(symbol)` triggers Apple's `\(rule.category)` requirement.",
                location: PrivacyLintCore.SourceLocation(
                    file: file.path,
                    line: loc.line,
                    column: loc.column
                ),
                remediation: "Declare one of [\(reasons)] for \(rule.category) in your PrivacyInfo.xcprivacy, or remove the call. Apple cites this in ITMS-91053 rejections."
            )
        )
    }
}
