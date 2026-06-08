import Foundation
import PrivacyLintRules

/// Reads the project's resolved dependencies — `Package.resolved` for Swift
/// Package Manager and `Podfile.lock` for CocoaPods — and cross-references
/// each entry against Apple's list of SDKs that must ship a privacy manifest.
///
/// The headline story: Firebase is widely used, ships its own manifest, but
/// pulls in `nanopb` as a transitive dependency. Older nanopb versions
/// shipped without a manifest, so apps were rejected with `ITMS-91061` even
/// though the developer never imported nanopb directly. This scanner
/// surfaces that.
///
/// Out of scope (v1):
/// - Validating the *contents* of a third-party manifest (only presence).
/// - Walking a Package.swift manifest that hasn't been resolved into
///   `Package.resolved` — we suggest the user run `swift package resolve`.
public struct DependencyResolver: ComplianceScanner {
    public let ruleIdentifier = "third-party-sdk-manifest"
    public let title = "Third-party SDK privacy manifests"

    /// Manifest requirements apply on every distributed platform, including
    /// macOS — so this scanner runs everywhere (unlike RequiredReasonAPIScanner).
    public var applicablePlatforms: Set<ApplePlatform> { Set(ApplePlatform.allCases) }

    public init() {}

    public func scan(_ context: ScanContext) throws -> [Violation] {
        let projectRoot = context.projectPath
        var violations: [Violation] = []

        let hasPackageSwift = context.dependencyManifests.contains {
            $0.lastPathComponent == "Package.swift"
        }
        let resolvedURL = projectRoot.appendingPathComponent("Package.resolved")
        let podfileLockURL = projectRoot.appendingPathComponent("Podfile.lock")
        let hasResolved = FileManager.default.fileExists(atPath: resolvedURL.path)
        let hasPodfileLock = FileManager.default.fileExists(atPath: podfileLockURL.path)

        // Scenario 6: nothing to check.
        guard hasResolved || hasPodfileLock || hasPackageSwift else { return [] }

        // Scenario 7: Package.swift exists but never resolved.
        if hasPackageSwift && !hasResolved {
            violations.append(
                Violation(
                    ruleIdentifier: ruleIdentifier,
                    severity: .warning,
                    message: "Package.swift is present but Package.resolved is missing — third-party SDK manifest checks were skipped.",
                    location: PrivacyLintCore.SourceLocation(file: projectRoot.appendingPathComponent("Package.swift").path, line: 1, column: 1),
                    remediation: "Run `swift package resolve` so PrivacyLint can verify each SDK ships a PrivacyInfo.xcprivacy."
                )
            )
        }

        var seen: Set<String> = []

        // SPM ----------------------------------------------------------------
        if hasResolved {
            do {
                let spmDeps = try parsePackageResolved(at: resolvedURL)
                for dep in spmDeps {
                    guard let canonical = ThirdPartySDKList.match(identity: dep.identity) else { continue }
                    guard seen.insert(canonical).inserted else { continue }
                    if let v = verifyManifest(
                        for: canonical,
                        depDescription: "\(dep.identity) (SwiftPM)",
                        checkoutDir: projectRoot.appendingPathComponent(".build/checkouts").appendingPathComponent(dep.identity)
                    ) {
                        violations.append(v)
                    }
                }
            } catch {
                violations.append(parseErrorViolation(at: resolvedURL, error: error))
            }
        }

        // CocoaPods ----------------------------------------------------------
        if hasPodfileLock {
            do {
                let pods = try parsePodfileLock(at: podfileLockURL)
                for pod in pods {
                    guard let canonical = ThirdPartySDKList.match(identity: pod) else { continue }
                    guard seen.insert(canonical).inserted else { continue }
                    if let v = verifyManifest(
                        for: canonical,
                        depDescription: "\(pod) (CocoaPods)",
                        checkoutDir: projectRoot.appendingPathComponent("Pods").appendingPathComponent(pod)
                    ) {
                        violations.append(v)
                    }
                }
            } catch {
                violations.append(parseErrorViolation(at: podfileLockURL, error: error))
            }
        }

        return violations
    }

    // MARK: - Per-dep verification

    private func verifyManifest(
        for canonical: String,
        depDescription: String,
        checkoutDir: URL
    ) -> Violation? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let checkoutExists = fm.fileExists(atPath: checkoutDir.path, isDirectory: &isDir) && isDir.boolValue

        if !checkoutExists {
            return Violation(
                ruleIdentifier: ruleIdentifier,
                severity: .warning,
                message: "`\(depDescription)` is on Apple's required-manifest list, but PrivacyLint could not find a local checkout at \(checkoutDir.lastPathComponent) to verify the manifest.",
                location: PrivacyLintCore.SourceLocation(file: checkoutDir.deletingLastPathComponent().path, line: 1, column: 1),
                remediation: "Run `swift package resolve` (SwiftPM) or `pod install` (CocoaPods), then re-scan. App Review rejects missing third-party manifests with ITMS-91061."
            )
        }

        // Manifest present → no violation. Silence on success is the right
        // default: the dev only wants to hear about problems, not roll calls.
        if findManifest(in: checkoutDir) != nil { return nil }

        return Violation(
            ruleIdentifier: ruleIdentifier,
            severity: .error,
            message: "`\(depDescription)` matches Apple's `\(canonical)` and is required to ship a privacy manifest, but no PrivacyInfo.xcprivacy was found in its checkout. App Review rejects this with ITMS-91061.",
            location: PrivacyLintCore.SourceLocation(file: checkoutDir.path, line: 1, column: 1),
            remediation: "Upgrade `\(canonical)` to a version that ships a privacy manifest, or contact the SDK author. Apple's list of required SDKs is at https://developer.apple.com/support/third-party-SDK-requirements/"
        )
    }

    private func findManifest(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            // Skip nested checkouts so we don't pick up another SDK's manifest.
            let parent = url.deletingLastPathComponent().lastPathComponent
            if parent == "Tests" || parent == "TestSupport" { continue }
            if url.lastPathComponent == "PrivacyInfo.xcprivacy" {
                return url
            }
        }
        return nil
    }

    private func parseErrorViolation(at url: URL, error: Error) -> Violation {
        Violation(
            ruleIdentifier: ruleIdentifier,
            severity: .error,
            message: "Failed to parse \(url.lastPathComponent): \(error.localizedDescription)",
            location: PrivacyLintCore.SourceLocation(file: url.path, line: 1, column: 1),
            remediation: "Re-run the package manager (`swift package resolve` or `pod install`) to regenerate the lockfile."
        )
    }
}

// MARK: - Lockfile parsers

enum LockfileError: Error, CustomStringConvertible {
    case malformedJSON
    case malformedPodfileLock
    case unreadable(String)

    var description: String {
        switch self {
        case .malformedJSON: return "not valid JSON"
        case .malformedPodfileLock: return "not a recognisable Podfile.lock"
        case .unreadable(let reason): return reason
        }
    }
}

struct ResolvedDependency: Equatable {
    let identity: String
    let version: String?
}

func parsePackageResolved(at url: URL) throws -> [ResolvedDependency] {
    let data = try Data(contentsOf: url)
    return try parsePackageResolved(data: data)
}

func parsePackageResolved(data: Data) throws -> [ResolvedDependency] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw LockfileError.malformedJSON
    }
    guard let pins = json["pins"] as? [[String: Any]] else {
        throw LockfileError.malformedJSON
    }
    return pins.compactMap { pin in
        guard let identity = pin["identity"] as? String else { return nil }
        let version = (pin["state"] as? [String: Any])?["version"] as? String
        return ResolvedDependency(identity: identity, version: version)
    }
}

func parsePodfileLock(at url: URL) throws -> [String] {
    let text: String
    do {
        text = try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw LockfileError.unreadable(error.localizedDescription)
    }
    return parsePodfileLock(text: text)
}

/// Extract pod names from a `Podfile.lock`. The file's `PODS:` section lists
/// every pod (including transitives) as `  - <Name> (<version>):`. We pull
/// `<Name>` and discard the subspec slash component since the SDK list is
/// rooted on the top-level pod name (`Firebase/Core` → match `Firebase`,
/// but `Firebase` itself will also be present).
func parsePodfileLock(text: String) -> [String] {
    var pods: Set<String> = []
    var inPodsSection = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "PODS:" { inPodsSection = true; continue }
        if inPodsSection {
            // Section ends at the next top-level key (no leading space).
            if !line.hasPrefix(" ") && !line.isEmpty { break }
        } else { continue }
        // Match `  - <Name> (...):` — only top-level pod entries (4 leading
        // spaces of indent in the Pods section).
        guard line.hasPrefix("  - ") else { continue }
        let after = line.dropFirst(4)
        // Drop everything from the first space + paren onward.
        guard let parenIndex = after.firstIndex(of: "(") else { continue }
        var name = String(after[..<parenIndex]).trimmingCharacters(in: .whitespaces)
        // Drop subspec component (`Firebase/Core` → `Firebase`) so we match
        // the top-level pod.
        if let slash = name.firstIndex(of: "/") { name = String(name[..<slash]) }
        if !name.isEmpty { pods.insert(name) }
    }
    return Array(pods).sorted()
}
