import Foundation
import PrivacyLintRules

/// Reconciles declared `PrivacyInfo.xcprivacy` entries against actual Required
/// Reason API usage in source code. This is the scanner that turns a code-level
/// "warning" into the App Review-grade `.error` (= ITMS-91053) — the rejection
/// developers wake up to.
///
/// Scope (v1):
/// - Cross-checks the `NSPrivacyAccessedAPITypes` section against
///   `RequiredReasonAPIScanner`'s detected usage.
/// - Validates per-entry shape: empty reasons, non-approved reason codes.
/// - Flags missing manifest when Required-Reason APIs are used.
/// - Flags dead declarations (declared category, no code uses it).
///
/// Out of scope (v1):
/// - `NSPrivacyTracking` / `NSPrivacyTrackingDomains` (TrackingDomainChecker).
/// - `NSPrivacyCollectedDataTypes` (future scanner).
public struct PrivacyManifestValidator: ComplianceScanner {
    public let ruleIdentifier = "privacy-manifest-validation"
    public let title = "Privacy manifest validation"

    /// Same scope as `RequiredReasonAPIScanner` — macOS is exempt from the
    /// `NSPrivacyAccessedAPITypes` requirement, so the cross-check is too.
    public var applicablePlatforms: Set<ApplePlatform> {
        Set(ApplePlatform.allCases.filter { $0.requiresRequiredReasonAPI })
    }

    private let usageDetector: RequiredReasonAPIScanner
    private let rules: [RequiredReasonAPI]

    public init(
        usageDetector: RequiredReasonAPIScanner = RequiredReasonAPIScanner(),
        rules: [RequiredReasonAPI] = RequiredReasonAPIs.all
    ) {
        self.usageDetector = usageDetector
        self.rules = rules
    }

    public func scan(_ context: ScanContext) throws -> [Violation] {
        let usage = try usageDetector.detectUsage(in: context)
        let usedCategories = Set(usage.map(\.category))

        // 1. No usage AND no manifest → nothing to validate.
        if usedCategories.isEmpty && context.privacyManifests.isEmpty {
            return []
        }

        // 2. Required-Reason APIs used but NO manifest anywhere → one clear
        //    summary error pointing at the first usage site so the developer
        //    can navigate to it. Don't generate a separate error per category
        //    — that's the kind of noisy output that makes developers
        //    distrust the tool.
        if context.privacyManifests.isEmpty {
            let firstHit = usage[0]
            let categories = usedCategories.sorted().joined(separator: ", ")
            return [
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .error,
                    message: "Your project uses Required Reason APIs (\(categories)) but contains no PrivacyInfo.xcprivacy. App Review will reject this with ITMS-91053.",
                    location: firstHit.location,
                    remediation: "Add a PrivacyInfo.xcprivacy file to your main bundle and declare an NSPrivacyAccessedAPITypes entry for each category listed above."
                )
            ]
        }

        // 3. Parse every manifest and union the declarations.
        var violations: [Violation] = []
        var declaredCategories: [String: [String]] = [:]  // category → union of reasons
        var manifestSourceForCategory: [String: URL] = [:]
        for manifestURL in context.privacyManifests {
            do {
                let manifest = try PrivacyManifestParser.parse(at: manifestURL)
                for entry in manifest.accessedAPITypes {
                    let existing = declaredCategories[entry.apiCategory] ?? []
                    declaredCategories[entry.apiCategory] = existing + entry.reasons
                    if manifestSourceForCategory[entry.apiCategory] == nil {
                        manifestSourceForCategory[entry.apiCategory] = manifestURL
                    }

                    // 5. Empty reasons → blocking error.
                    if entry.reasons.isEmpty {
                        violations.append(
                            Violation(
                                ruleIdentifier: ruleIdentifier,
                                severity: .error,
                                message: "The declaration of `\(entry.apiCategory)` in \(manifestURL.lastPathComponent) has no reasons. App Review rejects empty-reason entries with ITMS-91053.",
                                location: locationFor(file: manifestURL),
                                remediation: "Add at least one approved reason code, e.g. \(approvedReasons(for: entry.apiCategory))."
                            )
                        )
                    }

                    // 6. Non-approved reason code → warning.
                    if let rule = rules.first(where: { $0.category == entry.apiCategory }) {
                        let approved = Set(rule.approvedReasons)
                        for code in entry.reasons where !approved.contains(code) {
                            violations.append(
                                Violation(
                                    ruleIdentifier: ruleIdentifier,
                                    severity: .warning,
                                    message: "Reason `\(code)` for `\(entry.apiCategory)` is not in Apple's approved list. App Review may reject.",
                                    location: locationFor(file: manifestURL),
                                    remediation: "Replace with one of the approved reasons: \(rule.approvedReasons.joined(separator: ", "))."
                                )
                            )
                        }
                    }
                }
            } catch {
                violations.append(
                    Violation(
                        ruleIdentifier: ruleIdentifier,
                        severity: .error,
                        message: "Failed to parse \(manifestURL.path): \(error.localizedDescription)",
                        location: locationFor(file: manifestURL),
                        remediation: "Ensure the file is a valid binary or XML property list with the expected privacy-manifest schema."
                    )
                )
            }
        }

        let declaredCategorySet = Set(declaredCategories.keys)

        // 4. Undeclared category in use → blocking ITMS-91053. Group usages
        //    by category and point at the first occurrence in each.
        let usageByCategory = Dictionary(grouping: usage, by: \.category)
        for category in usageByCategory.keys.sorted() where !declaredCategorySet.contains(category) {
            let hits = usageByCategory[category]!
            let firstHit = hits[0]
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .error,
                    message: "`\(firstHit.symbol)` triggers `\(category)` but no PrivacyInfo.xcprivacy declares it. App Review rejects this with ITMS-91053.",
                    location: firstHit.location,
                    remediation: "Add an NSPrivacyAccessedAPITypes entry for \(category) in your PrivacyInfo.xcprivacy with reason \(approvedReasons(for: category))."
                )
            )
        }

        // 7. Declared but never used → dead-declaration warning.
        for category in declaredCategorySet.sorted() where !usedCategories.contains(category) {
            let manifestURL = manifestSourceForCategory[category]
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .warning,
                    message: "`\(category)` is declared in \(manifestURL?.lastPathComponent ?? "PrivacyInfo.xcprivacy") but no code uses it. Remove to avoid drift.",
                    location: manifestURL.map(locationFor(file:)),
                    remediation: "Delete the NSPrivacyAccessedAPITypes entry for \(category)."
                )
            )
        }

        return violations
    }

    private func approvedReasons(for category: String) -> String {
        guard let rule = rules.first(where: { $0.category == category }) else { return "<none>" }
        return rule.approvedReasons.joined(separator: " / ")
    }

    private func locationFor(file: URL) -> PrivacyLintCore.SourceLocation {
        PrivacyLintCore.SourceLocation(file: file.path, line: 1, column: 1)
    }
}
