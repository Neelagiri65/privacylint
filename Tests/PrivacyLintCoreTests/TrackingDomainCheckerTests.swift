import Foundation
import Testing
@testable import PrivacyLintCore
import PrivacyLintRules

/// The architectural gate for TrackingDomainChecker.
///
/// Scenario matrix (matrix IS the spec). v1 catches *static* string-literal
/// URLs and bare hostname literals. Dynamic / interpolated URLs are
/// deliberately out of scope — see README "Known limitations".
///
/// | #  | Scenario                                                                | Expected outcome                                |
/// | -- | ----------------------------------------------------------------------- | ----------------------------------------------- |
/// | 1  | Static tracker URL; manifest tracking=true, domain listed             | passed                                          |
/// | 2  | Static tracker URL; manifest tracking=false                            | .error (contradiction)                          |
/// | 3  | Static tracker URL; manifest tracking=true but domain absent           | .error (undeclared)                             |
/// | 4  | Static tracker URL; no manifest at all                                 | .error (one summary)                            |
/// | 5  | Only own-backend URLs                                                  | passed                                          |
/// | 6  | Dynamic URL (interpolation) → not detected (v1 limit)                  | no violation                                    |
/// | 7  | URL inside a comment                                                   | not detected (AST naturally skips)              |
/// | 8  | Tracker URL in test target                                             | not detected (ScanContext.testFiles excluded)   |
/// | 9  | Manifest declares domains; no code uses them                           | .warning dead declaration                       |
/// | 10 | URL with port/query/fragment                                           | host extracted; matched                         |
/// | 11 | applicablePlatforms = all (macOS too)                                  | runs on macOS-only project                      |
/// | 12 | Two manifests; union covers usage                                      | passed                                          |
/// | 13 | Subdomain (`connect.facebook.net`) covered by apex (`facebook.net`)    | apex declaration covers subdomain usage         |
/// | 14 | Bare hostname literal `"facebook.com"` (no scheme)                     | flagged                                         |
@Suite("TrackingDomainChecker — architectural gate")
struct TrackingDomainCheckerTests {

    // MARK: - Identity

    @Test func hasStableIdentifier() {
        #expect(TrackingDomainChecker().ruleIdentifier == "tracking-domain-declaration")
    }

    @Test func appliesToEveryPlatformIncludingMacOS() {
        #expect(TrackingDomainChecker().applicablePlatforms == Set(ApplePlatform.allCases))
    }

    // MARK: - Domain matcher

    @Test func apexHostsMatchDirectly() {
        #expect(KnownTrackerDomains.match(host: "facebook.com")?.network == "Meta")
        #expect(KnownTrackerDomains.match(host: "mixpanel.com")?.network == "Mixpanel")
    }

    @Test func subdomainsMatchTheirApex() {
        #expect(KnownTrackerDomains.match(host: "connect.facebook.net")?.network == "Meta")
        #expect(KnownTrackerDomains.match(host: "www.googletagmanager.com")?.network == "Google Tag Manager")
        // Case insensitive.
        #expect(KnownTrackerDomains.match(host: "WWW.Facebook.com")?.network == "Meta")
    }

    @Test func nonTrackerHostsReturnNil() {
        #expect(KnownTrackerDomains.match(host: "example.com") == nil)
        #expect(KnownTrackerDomains.match(host: "api.mybackend.io") == nil)
    }

    // MARK: - Source extraction

    private let checker = TrackingDomainChecker()
    private let tmpFile = URL(fileURLWithPath: "/tmp/Sample.swift")

    @Test func detectsStaticTrackerURL() {
        let source = """
        import Foundation
        let url = URL(string: "https://facebook.com/tr/event?id=123")
        """
        let hits = checker.extractHits(in: source, file: tmpFile)
        #expect(hits.count == 1)
        #expect(hits.first?.host == "facebook.com")
        #expect(hits.first?.network == "Meta")
        #expect(hits.first?.location.line == 2)
    }

    @Test func detectsSubdomainViaApex() {
        let source = """
        let url = "https://connect.facebook.net/en_US/fbevents.js"
        """
        let hits = checker.extractHits(in: source, file: tmpFile)
        #expect(hits.first?.host == "connect.facebook.net")
        #expect(hits.first?.network == "Meta")
    }

    @Test func detectsBareHostname() {
        let source = """
        let host = "facebook.com"
        """
        let hits = checker.extractHits(in: source, file: tmpFile)
        #expect(hits.count == 1)
        #expect(hits.first?.host == "facebook.com")
    }

    @Test func ignoresUrlsInComments() {
        let source = """
        // This used to call https://facebook.com/tr but no more.
        /// See https://mixpanel.com/api for details.
        let x = 1
        """
        let hits = checker.extractHits(in: source, file: tmpFile)
        #expect(hits.isEmpty)
    }

    @Test func ignoresInterpolatedURLs() {
        // Dynamic URLs are explicitly out of v1 scope.
        let source = #"""
        let host = "facebook.com"
        let url = "https://\(host)/tr/event"
        """#
        let hits = checker.extractHits(in: source, file: tmpFile)
        // The bare "facebook.com" literal IS detected (defensible — it's
        // still a static reference). The interpolated URL is not.
        #expect(hits.count == 1)
        #expect(hits[0].host == "facebook.com")
    }

    @Test func ignoresNonTrackerURLs() {
        let source = """
        let url = "https://api.mybackend.io/v1/widgets"
        let other = "https://example.com/api"
        """
        let hits = checker.extractHits(in: source, file: tmpFile)
        #expect(hits.isEmpty)
    }

    @Test func extractsHostFromURLWithPortAndQuery() {
        let source = """
        let url = "https://facebook.com:443/tr?id=123#frag"
        """
        let hits = checker.extractHits(in: source, file: tmpFile)
        #expect(hits.first?.host == "facebook.com")
    }

    // MARK: - End-to-end matrix

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-tdc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSource(_ text: String, in dir: URL, named: String = "App.swift") throws -> URL {
        let url = dir.appendingPathComponent(named)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeManifest(
        tracking: Bool,
        trackingDomains: [String],
        named name: String = "PrivacyInfo.xcprivacy",
        in dir: URL
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dict: [String: Any] = [
            "NSPrivacyTracking": tracking,
            "NSPrivacyTrackingDomains": trackingDomains
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    private let trackerSource = """
    import Foundation
    let url = URL(string: "https://facebook.com/tr/event?id=1")
    """

    @Test func scenario1_declaredCorrectlyPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource(trackerSource, in: dir)
        let m = try writeManifest(tracking: true, trackingDomains: ["facebook.com"], in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], privacyManifests: [m], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        #expect(violations.isEmpty, "Unexpected: \(violations.map(\.message))")
    }

    @Test func scenario2_trackingFalseContradiction() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource(trackerSource, in: dir)
        let m = try writeManifest(tracking: false, trackingDomains: [], in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], privacyManifests: [m], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        let contradiction = violations.first { $0.message.contains("contradiction") }
        let v = try #require(contradiction)
        #expect(v.severity == .error)
    }

    @Test func scenario3_undeclaredDomainProducesError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource(trackerSource, in: dir)
        let m = try writeManifest(tracking: true, trackingDomains: ["analytics.google.com"], in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], privacyManifests: [m], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        let v = try #require(violations.first { $0.message.contains("facebook.com") })
        #expect(v.severity == .error)
        #expect(v.message.contains("NSPrivacyTrackingDomains"))
    }

    @Test func scenario4_noManifestProducesOneSummaryError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource("""
        import Foundation
        let f = URL(string: "https://facebook.com/tr")
        let m = URL(string: "https://mixpanel.com/api/v1/track")
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        #expect(violations.count == 1)
        let v = try #require(violations.first)
        #expect(v.severity == .error)
        #expect(v.message.contains("Meta"))
        #expect(v.message.contains("Mixpanel"))
    }

    @Test func scenario5_ownBackendOnlyPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource("""
        let url = "https://api.mybackend.io/v1/widgets"
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        #expect(violations.isEmpty)
    }

    @Test func scenario9_deadDeclarationWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource("import Foundation\nlet x = 1", in: dir)
        let m = try writeManifest(tracking: true, trackingDomains: ["facebook.com"], in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], privacyManifests: [m], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        let dead = violations.first { $0.message.contains("no static code reference") }
        let v = try #require(dead)
        #expect(v.severity == .warning)
    }

    @Test func scenario11_macOSOnlyProjectStillRuns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource(trackerSource, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], platforms: [.macOS])
        let result = RuleRegistry().run(context)
        let tdc = try #require(result.outcomes.first { $0.ruleIdentifier == "tracking-domain-declaration" })
        #expect(tdc.status == .failed)
        #expect(!tdc.violations.isEmpty)
    }

    @Test func scenario13_apexDeclarationCoversSubdomainUsage() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try writeSource("""
        let url = "https://connect.facebook.net/en_US/fbevents.js"
        """, in: dir)
        let m = try writeManifest(tracking: true, trackingDomains: ["facebook.net"], in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [s], privacyManifests: [m], platforms: [.iOS])
        let violations = try TrackingDomainChecker().scan(context)
        #expect(violations.isEmpty, "Unexpected: \(violations.map(\.message))")
    }
}
