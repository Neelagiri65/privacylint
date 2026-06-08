import Foundation
import PrivacyLintRules
import SwiftParser
import SwiftSyntax

/// Detects calls or string literals that reference Apple-flagged tracking
/// domains and reconciles them against the project's
/// `NSPrivacyTracking` / `NSPrivacyTrackingDomains` declarations.
///
/// Scope (v1):
/// - Static URL string literals only (`"https://facebook.com/tr/"`).
/// - Bare hostname literals (`"facebook.com"`).
/// - Subdomain matching against apex tracker hosts.
///
/// Out of scope (v1) — documented in README:
/// - Runtime-constructed URLs (`base + "/track"`, `"https://\(h)/x"`).
/// - URLs in Info.plist / `.strings` / `.json` resource files.
/// - URLs reached through SDK calls (`Analytics.log(...)`) where the SDK
///   has its own endpoint config. SDKs themselves are flagged by
///   `DependencyResolver`; this scanner is the source-code complement.
public struct TrackingDomainChecker: ComplianceScanner {
    public let ruleIdentifier = "tracking-domain-declaration"
    public let title = "Tracking domain declarations"

    /// Tracking declarations are required on every distributed platform,
    /// including macOS — same scope as `DependencyResolver`.
    public var applicablePlatforms: Set<ApplePlatform> { Set(ApplePlatform.allCases) }

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        // 1. Walk source for static tracker references.
        var usage: [TrackerHit] = []
        for url in context.sourceFiles {
            let source = try String(contentsOf: url, encoding: .utf8)
            usage.append(contentsOf: extractHits(in: source, file: url))
        }

        // 2. Parse manifests for tracking declarations.
        var manifestTrackingFlag: Bool? = nil
        var declaredDomains: Set<String> = []
        var firstManifestForDomain: [String: URL] = [:]
        var violations: [Violation] = []

        for manifestURL in context.privacyManifests {
            do {
                let manifest = try PrivacyManifestParser.parse(at: manifestURL)
                // Any tracking=true wins (union semantics across manifests).
                if manifest.tracking { manifestTrackingFlag = true }
                else if manifestTrackingFlag == nil { manifestTrackingFlag = false }
                for domain in manifest.trackingDomains {
                    let lower = domain.lowercased()
                    declaredDomains.insert(lower)
                    if firstManifestForDomain[lower] == nil {
                        firstManifestForDomain[lower] = manifestURL
                    }
                }
            } catch {
                violations.append(
                    Violation(
                        ruleIdentifier: ruleIdentifier,
                        severity: .error,
                        message: "Failed to parse \(manifestURL.path): \(error.localizedDescription)",
                        location: PrivacyLintCore.SourceLocation(file: manifestURL.path, line: 1, column: 1),
                        remediation: "Ensure the file is a valid property list."
                    )
                )
            }
        }

        let usedDomains = Set(usage.map { $0.host.lowercased() })

        // 3. Nothing to report.
        if usage.isEmpty && declaredDomains.isEmpty && manifestTrackingFlag != true {
            return violations
        }

        // 4. Tracker URLs in code, no manifest at all.
        if !usage.isEmpty && context.privacyManifests.isEmpty {
            let networks = Set(usage.map(\.network)).sorted().joined(separator: ", ")
            let first = usage[0]
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .error,
                    message: "Your project calls tracking domains (\(networks)) but contains no PrivacyInfo.xcprivacy. App Review rejects undeclared tracking under the privacy-manifest rules.",
                    location: first.location,
                    remediation: "Add a PrivacyInfo.xcprivacy with NSPrivacyTracking=true and list each domain in NSPrivacyTrackingDomains."
                )
            )
            return violations
        }

        // 5. Tracker URLs in code + tracking=false → contradiction.
        if !usage.isEmpty && manifestTrackingFlag == false {
            let first = usage[0]
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .error,
                    message: "Your code calls `\(first.host)` (\(first.network)) but the manifest sets NSPrivacyTracking=false. App Review rejects this contradiction.",
                    location: first.location,
                    remediation: "Either set NSPrivacyTracking=true and declare each tracking domain in NSPrivacyTrackingDomains, or remove the tracker call."
                )
            )
            // When the contradiction error has already fired, suppress the
            // per-domain "undeclared" noise — one strong error is more
            // actionable than five.
            return violations
        }

        // 6. Tracker URL not declared in NSPrivacyTrackingDomains.
        let usageByDomain = Dictionary(grouping: usage, by: { $0.host.lowercased() })
        for domain in usageByDomain.keys.sorted() where !declaredDomains.contains(domain) {
            // Subdomain may be covered by an apex declaration.
            let coveredByApex = declaredDomains.contains { apex in domain.hasSuffix("." + apex) }
            if coveredByApex { continue }
            let first = usageByDomain[domain]![0]
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .error,
                    message: "Code calls `\(domain)` (\(first.network)) but this domain is not listed in NSPrivacyTrackingDomains. App Review rejects undeclared tracking domains.",
                    location: first.location,
                    remediation: "Add `\(domain)` to NSPrivacyTrackingDomains in your PrivacyInfo.xcprivacy."
                )
            )
        }

        // 7. Domain declared but never used → dead-declaration warning.
        for domain in declaredDomains.sorted() where !usedDomains.contains(domain) {
            let coveredBySubdomain = usedDomains.contains { used in used.hasSuffix("." + domain) }
            if coveredBySubdomain { continue }
            let manifestURL = firstManifestForDomain[domain]
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .warning,
                    message: "`\(domain)` is declared in \(manifestURL?.lastPathComponent ?? "PrivacyInfo.xcprivacy") but no static code reference was found. Remove if unused.",
                    location: manifestURL.map { PrivacyLintCore.SourceLocation(file: $0.path, line: 1, column: 1) },
                    remediation: "Delete `\(domain)` from NSPrivacyTrackingDomains, or check whether your code constructs the URL dynamically (PrivacyLint v1 only detects static URL literals)."
                )
            )
        }

        return violations
    }

    // MARK: - Extraction

    struct TrackerHit: Equatable {
        let host: String
        let network: String
        let location: PrivacyLintCore.SourceLocation
    }

    /// Test-friendly entry point — skips IO.
    func extractHits(in source: String, file: URL) -> [TrackerHit] {
        let tree = Parser.parse(source: source)
        let visitor = TrackingDomainVisitor(file: file, tree: tree)
        visitor.walk(tree)
        return visitor.hits
    }
}

private final class TrackingDomainVisitor: SyntaxVisitor {
    private let file: URL
    private let converter: SourceLocationConverter
    var hits: [TrackingDomainChecker.TrackerHit] = []

    init(file: URL, tree: SourceFileSyntax) {
        self.file = file
        self.converter = SourceLocationConverter(fileName: file.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Only fully-static literals — any interpolation segment makes the
        // value dynamic, and v1 is explicit about not attempting that.
        var literal = ""
        for segment in node.segments {
            guard let strSeg = segment.as(StringSegmentSyntax.self) else {
                return .visitChildren
            }
            literal += strSeg.content.text
        }
        guard !literal.isEmpty else { return .visitChildren }

        if let host = extractHost(from: literal),
           let tracker = KnownTrackerDomains.match(host: host) {
            let loc = node.startLocation(converter: converter)
            hits.append(
                TrackingDomainChecker.TrackerHit(
                    host: host.lowercased(),
                    network: tracker.network,
                    location: PrivacyLintCore.SourceLocation(file: file.path, line: loc.line, column: loc.column)
                )
            )
        }
        return .visitChildren
    }

    /// Pull a hostname out of a literal. Handles `https://host/path`,
    /// `http://host`, bare `host.com/x`, bare `host.com`. Returns nil for
    /// anything that doesn't look like a hostname.
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
