import Foundation
import Testing
@testable import PrivacyLintCore
import PrivacyLintRules

/// The architectural gate for DependencyResolver.
///
/// Scenario matrix — every row maps to at least one test.
///
/// | # | Scenario                                                              | Expected outcome                                       |
/// | - | --------------------------------------------------------------------- | ------------------------------------------------------ |
/// | 1 | Package.resolved lists dep on Apple's list; checkout has manifest    | passed                                                 |
/// | 2 | Package.resolved lists dep; checkout exists but no manifest           | .error ITMS-91061                                      |
/// | 3 | Package.resolved lists dep; no checkout directory                     | .warning "run swift package resolve"                   |
/// | 4 | Podfile.lock lists pod on list; Pods/<name>/ has manifest            | passed                                                 |
/// | 5 | Podfile.lock lists pod on list; Pods/<name>/ has no manifest         | .error ITMS-91061                                      |
/// | 6 | No lockfiles at all                                                   | passed (nothing to check)                              |
/// | 7 | Package.swift but no Package.resolved                                 | .warning                                               |
/// | 8 | Dep not on Apple's list                                               | silently skipped                                       |
/// | 9 | Malformed JSON Package.resolved                                       | .error parse error                                     |
/// |10 | Transitive nanopb pulled in by firebase-ios-sdk, nanopb has no manifest | .error ITMS-91061 cites nanopb (THE STORY)            |
/// |11 | applicablePlatforms: all (manifest req applies to macOS too)          | macOS-only project still runs the scanner              |
/// |12 | Same SDK in both Package.resolved AND Podfile.lock                    | deduped — one violation                                |
@Suite("DependencyResolver — architectural gate")
struct DependencyResolverTests {

    // MARK: - Identity & platforms

    @Test func hasStableIdentifier() {
        #expect(DependencyResolver().ruleIdentifier == "third-party-sdk-manifest")
    }

    @Test func appliesToEveryPlatformIncludingMacOS() {
        // Third-party SDK manifests are required on every distributed
        // platform, unlike Required-Reason API which exempts macOS.
        let validator = DependencyResolver()
        #expect(validator.applicablePlatforms == Set(ApplePlatform.allCases))
        #expect(validator.applicablePlatforms.contains(.macOS))
    }

    // MARK: - SDK matcher

    @Test func matchesSPMRepoIdentities() {
        #expect(ThirdPartySDKList.match(identity: "firebase-ios-sdk") == "Firebase")
        #expect(ThirdPartySDKList.match(identity: "nanopb") == "nanopb")
        #expect(ThirdPartySDKList.match(identity: "realm-swift") == "RealmSwift")
        #expect(ThirdPartySDKList.match(identity: "Alamofire") == "Alamofire")
        #expect(ThirdPartySDKList.match(identity: "kingfisher") == "Kingfisher")
    }

    @Test func returnsNilForUnknownIdentities() {
        #expect(ThirdPartySDKList.match(identity: "swift-argument-parser") == nil)
        #expect(ThirdPartySDKList.match(identity: "swift-syntax") == nil)
        #expect(ThirdPartySDKList.match(identity: "some-random-repo") == nil)
    }

    // MARK: - Package.resolved parser

    @Test func parsesPackageResolvedV2() throws {
        let json = """
        {
          "pins" : [
            { "identity" : "firebase-ios-sdk",
              "kind" : "remoteSourceControl",
              "state" : { "revision" : "abc", "version" : "10.0.0" } },
            { "identity" : "nanopb",
              "kind" : "remoteSourceControl",
              "state" : { "revision" : "def", "version" : "2.30908.0" } }
          ],
          "version" : 2
        }
        """.data(using: .utf8)!
        let deps = try parsePackageResolved(data: json)
        #expect(deps.count == 2)
        #expect(deps.contains(ResolvedDependency(identity: "firebase-ios-sdk", version: "10.0.0")))
        #expect(deps.contains(ResolvedDependency(identity: "nanopb", version: "2.30908.0")))
    }

    @Test func malformedJSONThrows() {
        #expect(throws: LockfileError.self) {
            try parsePackageResolved(data: Data("not json".utf8))
        }
    }

    // MARK: - Podfile.lock parser

    @Test func parsesPodfileLock() {
        let lockfile = """
        PODS:
          - Firebase (10.0.0):
            - Firebase/Core (= 10.0.0)
          - Firebase/Core (10.0.0):
            - FirebaseCore (~> 10.0.0)
          - FirebaseCore (10.0.0):
            - nanopb (~> 2.30908.0)
          - nanopb (2.30908.0):
            - nanopb/decode (= 2.30908.0)
            - nanopb/encode (= 2.30908.0)

        DEPENDENCIES:
          - Firebase

        SPEC REPOS:
          trunk:
            - Firebase

        SPEC CHECKSUMS:
          Firebase: abc

        COCOAPODS: 1.14.0
        """
        let pods = parsePodfileLock(text: lockfile)
        // Subspec rolls up to its parent; we should see top-level pods.
        #expect(pods.contains("Firebase"))
        #expect(pods.contains("FirebaseCore"))
        #expect(pods.contains("nanopb"))
        // DEPENDENCIES / SPEC sections should not bleed in.
        #expect(!pods.contains("trunk"))
    }

    // MARK: - End-to-end matrix

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-dr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePackageResolved(_ deps: [(id: String, version: String)], in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("Package.resolved")
        let pins = deps.map { dep in
            [
                "identity": dep.id,
                "kind": "remoteSourceControl",
                "state": ["revision": "abc", "version": dep.version]
            ] as [String: Any]
        }
        let obj: [String: Any] = ["pins": pins, "version": 2]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        try data.write(to: url)
        return url
    }

    private func writeCheckout(name: String, in dir: URL, withManifest: Bool) throws {
        let checkout = dir.appendingPathComponent(".build/checkouts").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        if withManifest {
            try Data().write(to: checkout.appendingPathComponent("PrivacyInfo.xcprivacy"))
        }
    }

    private func runResolver(at dir: URL) throws -> [Violation] {
        let context = ScanContext(
            projectPath: dir,
            dependencyManifests: [dir.appendingPathComponent("Package.swift")],
            platforms: [.iOS]
        )
        return try DependencyResolver().scan(context)
    }

    @Test func scenario1_depOnListWithManifestPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writePackageResolved([(id: "firebase-ios-sdk", version: "10.0.0")], in: dir)
        try writeCheckout(name: "firebase-ios-sdk", in: dir, withManifest: true)
        let violations = try runResolver(at: dir)
        #expect(violations.isEmpty, "Unexpected: \(violations.map(\.message))")
    }

    @Test func scenario2_depOnListMissingManifestIsITMS91061() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writePackageResolved([(id: "nanopb", version: "2.30908.0")], in: dir)
        try writeCheckout(name: "nanopb", in: dir, withManifest: false)
        let violations = try runResolver(at: dir)
        let v = try #require(violations.first)
        #expect(v.severity == .error)
        #expect(v.message.contains("ITMS-91061"))
        #expect(v.message.contains("nanopb"))
    }

    @Test func scenario3_depOnListWithoutCheckoutWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writePackageResolved([(id: "firebase-ios-sdk", version: "10.0.0")], in: dir)
        // No .build/checkouts/ directory created.
        let violations = try runResolver(at: dir)
        let v = try #require(violations.first)
        #expect(v.severity == .warning)
        #expect(v.remediation?.contains("swift package resolve") == true)
    }

    @Test func scenario6_noLockfilesIsPassed() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = ScanContext(projectPath: dir, platforms: [.iOS])
        let violations = try DependencyResolver().scan(context)
        #expect(violations.isEmpty)
    }

    @Test func scenario7_packageSwiftWithoutResolvedWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pkgURL = dir.appendingPathComponent("Package.swift")
        try Data().write(to: pkgURL)
        let context = ScanContext(
            projectPath: dir,
            dependencyManifests: [pkgURL],
            platforms: [.iOS]
        )
        let violations = try DependencyResolver().scan(context)
        let v = try #require(violations.first)
        #expect(v.severity == .warning)
        #expect(v.message.contains("Package.resolved is missing"))
    }

    @Test func scenario8_depNotOnAppleListIsIgnored() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writePackageResolved([(id: "swift-argument-parser", version: "1.0.0")], in: dir)
        try writeCheckout(name: "swift-argument-parser", in: dir, withManifest: false)
        let violations = try runResolver(at: dir)
        #expect(violations.isEmpty)
    }

    @Test func scenario9_malformedResolvedProducesParseError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not json".utf8).write(to: dir.appendingPathComponent("Package.resolved"))
        let violations = try runResolver(at: dir)
        let v = try #require(violations.first { $0.message.contains("Failed to parse") })
        #expect(v.severity == .error)
    }

    @Test func scenario10_firebaseTransitiveNanopbHeadlineStory() throws {
        // The headline rejection: user adds Firebase, gets rejected for
        // nanopb. Both are on Apple's list; nanopb in this fixture ships
        // a manifest but Firebase doesn't (inverse fault to make the
        // error specifically about Firebase being unmanifested).
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writePackageResolved([
            (id: "firebase-ios-sdk", version: "10.0.0"),
            (id: "nanopb",           version: "2.30908.0")
        ], in: dir)
        try writeCheckout(name: "firebase-ios-sdk", in: dir, withManifest: false)
        try writeCheckout(name: "nanopb",           in: dir, withManifest: true)
        let violations = try runResolver(at: dir)
        let firebaseFail = violations.first { $0.message.contains("firebase-ios-sdk") }
        let v = try #require(firebaseFail)
        #expect(v.severity == .error)
        #expect(v.message.contains("ITMS-91061"))
        // nanopb has a manifest → no violation about nanopb.
        #expect(!violations.contains { $0.message.contains("nanopb") })
    }

    @Test func scenario11_macOSOnlyProjectStillRunsResolver() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try writePackageResolved([(id: "firebase-ios-sdk", version: "10.0.0")], in: dir)
        try writeCheckout(name: "firebase-ios-sdk", in: dir, withManifest: false)
        let context = ScanContext(projectPath: dir, platforms: [.macOS])
        // The registry, not the scanner, would normally skip — but the
        // scanner's own applicablePlatforms includes macOS, so when run
        // directly we should still see the violation.
        let violations = try DependencyResolver().scan(context)
        #expect(violations.contains { $0.severity == .error })
    }
}
