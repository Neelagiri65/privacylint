import Foundation
import Testing
@testable import PrivacyLintCore

/// The architectural gate for platform-aware scanning.
///
/// Matrix (mirrors docs/research-platform-awareness.md §4):
///
/// | Project platforms      | Required-Reason scanner runs? |
/// | ---------------------- | ----------------------------- |
/// | `[.macOS]`             | NO  → status .skippedForPlatform |
/// | `[.iOS]`               | YES                              |
/// | `[.iOS, .macOS]`       | YES (one applicable is enough)  |
/// | `[]` (unknown)         | YES (conservative)              |
/// | `[.macCatalyst]`       | YES (treated as iOS-family)      |
@Suite("Platform awareness — architectural gate")
struct PlatformAwarenessTests {

    // MARK: - ApplePlatform matrix

    @Test func macOSIsTheSoleExemptionFromRequiredReason() {
        for platform in ApplePlatform.allCases {
            if platform == .macOS {
                #expect(!platform.requiresRequiredReasonAPI)
            } else {
                #expect(platform.requiresRequiredReasonAPI, "\(platform) should require Required-Reason API")
            }
        }
    }

    @Test func everyPlatformRequiresAPrivacyManifest() {
        for platform in ApplePlatform.allCases {
            #expect(platform.requiresPrivacyManifest)
        }
    }

    @Test func mapsSPMPlatformNames() {
        #expect(ApplePlatform.fromSPMName("ios") == .iOS)
        #expect(ApplePlatform.fromSPMName("macos") == .macOS)
        #expect(ApplePlatform.fromSPMName("visionos") == .visionOS)
        #expect(ApplePlatform.fromSPMName("watchos") == .watchOS)
        #expect(ApplePlatform.fromSPMName("tvos") == .tvOS)
        #expect(ApplePlatform.fromSPMName("maccatalyst") == .macCatalyst)
        #expect(ApplePlatform.fromSPMName("driverkit") == nil) // not in our enum
        #expect(ApplePlatform.fromSPMName("Linux") == nil)
    }

    // MARK: - RuleRegistry honours applicability

    private func contextWith(platforms: Set<ApplePlatform>) -> ScanContext {
        ScanContext(
            projectPath: URL(fileURLWithPath: "/tmp/sample"),
            sourceFiles: [],
            platforms: platforms
        )
    }

    @Test func macOSOnlyProjectSkipsRequiredReasonScanner() {
        let result = RuleRegistry().run(contextWith(platforms: [.macOS]))
        let rra = result.outcomes.first { $0.ruleIdentifier == "required-reason-api" }
        #expect(rra?.status == .skippedForPlatform)
        #expect(rra?.violations.isEmpty == true)
        #expect(result.detectedPlatforms == [.macOS])
    }

    @Test func iOSOnlyProjectRunsRequiredReasonScanner() {
        let result = RuleRegistry().run(contextWith(platforms: [.iOS]))
        let rra = result.outcomes.first { $0.ruleIdentifier == "required-reason-api" }
        #expect(rra?.status == .passed) // no sourceFiles, no violations
    }

    @Test func multiPlatformProjectRunsRequiredReasonScannerWhenAnyApplies() {
        let result = RuleRegistry().run(contextWith(platforms: [.iOS, .macOS]))
        let rra = result.outcomes.first { $0.ruleIdentifier == "required-reason-api" }
        #expect(rra?.status == .passed)
    }

    @Test func emptyPlatformsAssumeAllAndRunEverything() {
        let result = RuleRegistry().run(contextWith(platforms: []))
        let rra = result.outcomes.first { $0.ruleIdentifier == "required-reason-api" }
        #expect(rra?.status == .passed)
        // Scaffolded scanners are visible as .notImplemented, not silently
        // dropped. Drops by one each time we ship a new scanner — currently
        // RequiredReason + PrivacyManifestValidator are implemented, leaving
        // DependencyResolver + TrackingDomainChecker + AIConsentDetector.
        let nyi = result.outcomes.filter { $0.status == .notImplemented }
        #expect(nyi.count == 3)
    }

    @Test func macCatalystCountsAsIOSFamily() {
        let result = RuleRegistry().run(contextWith(platforms: [.macCatalyst]))
        let rra = result.outcomes.first { $0.ruleIdentifier == "required-reason-api" }
        #expect(rra?.status == .passed)
    }

    // MARK: - RequiredReasonAPIScanner is genuinely silent on macOS

    @Test func macOSContextProducesNoRequiredReasonViolationsEvenWithSourceMatches() throws {
        // Write a real Swift file containing UserDefaults.standard, then
        // confirm that on a macOS-only context the registry returns
        // .skippedForPlatform with zero violations — no false positives.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-platform-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sourceURL = tmp.appendingPathComponent("App.swift")
        try """
        import Foundation
        let v = UserDefaults.standard.bool(forKey: "k")
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let context = ScanContext(
            projectPath: tmp,
            sourceFiles: [sourceURL],
            platforms: [.macOS]
        )
        let result = RuleRegistry().run(context)
        let rra = try #require(result.outcomes.first { $0.ruleIdentifier == "required-reason-api" })
        #expect(rra.status == .skippedForPlatform)
        #expect(rra.violations.isEmpty)
    }

    // MARK: - PlatformDetector

    // Tests use the JSON-parsing entry point directly. Calling
    // `swift package describe` reentrantly inside `swift test` deadlocks
    // on the SPM build lock.

    @Test func parsesSPMDescribeJSONForMacOSOnlyProject() {
        let json = """
        {
          "name": "Demo",
          "platforms": [{"name": "macos", "version": "13.0"}]
        }
        """.data(using: .utf8)!
        let result = PlatformDetector.parseDescribeJSON(json)
        #expect(result.platforms == [.macOS])
    }

    @Test func parsesSPMDescribeJSONForUniversalProject() {
        let json = """
        {
          "name": "Universal",
          "platforms": [
            {"name": "ios", "version": "17.0"},
            {"name": "macos", "version": "13.0"},
            {"name": "visionos", "version": "1.0"}
          ]
        }
        """.data(using: .utf8)!
        let result = PlatformDetector.parseDescribeJSON(json)
        #expect(result.platforms == [.iOS, .macOS, .visionOS])
    }

    @Test func emptyPlatformsArrayMeansUnknownNotSilence() {
        let json = """
        {"name": "Lib", "platforms": []}
        """.data(using: .utf8)!
        let result = PlatformDetector.parseDescribeJSON(json)
        #expect(result.platforms.isEmpty)
        #expect(!result.note.isEmpty)
    }

    @Test func unknownPlatformNamesAreReportedNotDropped() {
        let json = """
        {
          "name": "Mixed",
          "platforms": [
            {"name": "ios", "version": "17.0"},
            {"name": "linux", "version": "6.0"}
          ]
        }
        """.data(using: .utf8)!
        let result = PlatformDetector.parseDescribeJSON(json)
        #expect(result.platforms == [.iOS])
        #expect(result.note.contains("linux"))
    }

    @Test func malformedJSONFallsBackToEmpty() {
        let result = PlatformDetector.parseDescribeJSON(Data("not json".utf8))
        #expect(result.platforms.isEmpty)
        #expect(result.note.contains("could not parse"))
    }

    @Test func detectorReturnsEmptyForUnknownProject() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-no-manifest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let result = PlatformDetector.detect(at: tmp)
        #expect(result.platforms.isEmpty)
        #expect(result.note.isEmpty)
    }
}
