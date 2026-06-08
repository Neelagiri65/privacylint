import Foundation
import Testing
@testable import PrivacyLintCore

@Suite("TerminalReporter")
struct TerminalReporterTests {

    private func makeResult(
        platforms: [ApplePlatform] = [.iOS],
        outcomes: [CheckOutcome]
    ) -> ScanResult {
        ScanResult(
            projectPath: "/tmp/demo",
            detectedPlatforms: platforms,
            outcomes: outcomes
        )
    }

    // MARK: - Without colour (deterministic strings)

    @Test func rendersPassedScannerCleanly() {
        let outcome = CheckOutcome(
            ruleIdentifier: "required-reason-api",
            title: "Required Reason API usage",
            status: .passed,
            applicablePlatforms: [.iOS],
            violations: []
        )
        let out = TerminalReporter(useColour: false).render(makeResult(outcomes: [outcome]))
        #expect(out.contains("[required-reason-api]"))
        #expect(out.contains("Required Reason API usage"))
        #expect(out.contains("✓ passed"))
        #expect(out.contains("Status: PASSED"))
    }

    @Test func rendersFailedScannerWithErrorBlock() {
        let v = Violation(
            ruleIdentifier: "privacy-manifest-validation",
            severity: .error,
            message: "`UserDefaults` triggers ITMS-91053.",
            location: PrivacyLintCore.SourceLocation(file: "/tmp/demo/Sources/App.swift", line: 5, column: 13),
            remediation: "Declare CA92.1 in PrivacyInfo.xcprivacy."
        )
        let outcome = CheckOutcome(
            ruleIdentifier: "privacy-manifest-validation",
            title: "Privacy manifest validation",
            status: .failed,
            applicablePlatforms: [.iOS],
            violations: [v]
        )
        let out = TerminalReporter(useColour: false).render(makeResult(outcomes: [outcome]))
        #expect(out.contains("✗ failed"))
        #expect(out.contains("1 error"))
        #expect(out.contains("error"))
        // Path is RELATIVE to projectPath, not absolute.
        #expect(out.contains("Sources/App.swift:5:13"))
        #expect(!out.contains("/tmp/demo/Sources/App.swift:5:13"))
        #expect(out.contains("ITMS-91053"))
        #expect(out.contains("fix-it: Declare CA92.1"))
        #expect(out.contains("Status: FAILED"))
        #expect(out.contains("App Review will block"))
    }

    @Test func skippedForPlatformShowsApplicableSet() {
        let outcome = CheckOutcome(
            ruleIdentifier: "required-reason-api",
            title: "Required Reason API usage",
            status: .skippedForPlatform,
            applicablePlatforms: [.iOS, .iPadOS, .visionOS]
        )
        let out = TerminalReporter(useColour: false).render(
            makeResult(platforms: [.macOS], outcomes: [outcome])
        )
        #expect(out.contains("— skipped"))
        #expect(out.contains("applies to:"))
        #expect(out.contains("iOS"))
        #expect(out.contains("visionOS"))
    }

    @Test func notImplementedScannerStillAppearsButMarkedAsSuch() {
        let outcome = CheckOutcome(
            ruleIdentifier: "some-rule",
            title: "Some Rule",
            status: .notImplemented
        )
        let out = TerminalReporter(useColour: false).render(makeResult(outcomes: [outcome]))
        #expect(out.contains("[some-rule]"))
        #expect(out.contains("— not implemented"))
    }

    // MARK: - Summary

    @Test func summaryAggregatesAcrossOutcomes() {
        let outcomes = [
            CheckOutcome(ruleIdentifier: "a", title: "A", status: .passed),
            CheckOutcome(ruleIdentifier: "b", title: "B", status: .failed, violations: [
                Violation(ruleIdentifier: "b", severity: .error, message: "oops")
            ]),
            CheckOutcome(ruleIdentifier: "c", title: "C", status: .skippedForPlatform)
        ]
        let out = TerminalReporter(useColour: false).render(makeResult(outcomes: outcomes))
        #expect(out.contains("✓ 1 passed"))
        #expect(out.contains("✗ 1 failed"))
        #expect(out.contains("— 1 skipped"))
        #expect(out.contains("errors: 1"))
        #expect(out.contains("Status: FAILED"))
    }

    @Test func headerListsDetectedPlatforms() {
        let outcomes = [
            CheckOutcome(ruleIdentifier: "a", title: "A", status: .passed)
        ]
        let out = TerminalReporter(useColour: false).render(
            makeResult(platforms: [.iOS, .macOS], outcomes: outcomes)
        )
        #expect(out.contains("Platforms: iOS, macOS"))
    }

    @Test func emptyPlatformsShowsFallbackText() {
        let outcomes = [
            CheckOutcome(ruleIdentifier: "a", title: "A", status: .passed)
        ]
        let out = TerminalReporter(useColour: false).render(
            makeResult(platforms: [], outcomes: outcomes)
        )
        #expect(out.contains("not detected"))
    }

    // MARK: - Colour

    @Test func ansiCodesAppearWhenColourIsEnabled() {
        let outcome = CheckOutcome(
            ruleIdentifier: "x", title: "X", status: .failed,
            violations: [Violation(ruleIdentifier: "x", severity: .error, message: "boom")]
        )
        let coloured = TerminalReporter(useColour: true).render(makeResult(outcomes: [outcome]))
        let plain = TerminalReporter(useColour: false).render(makeResult(outcomes: [outcome]))
        #expect(coloured.contains("\u{001B}["))
        #expect(!plain.contains("\u{001B}["))
    }

    // MARK: - Long-line wrapping

    @Test func longMessageIsWrappedNotTruncated() {
        let longMessage = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        let v = Violation(
            ruleIdentifier: "x", severity: .warning,
            message: longMessage,
            location: PrivacyLintCore.SourceLocation(file: "/tmp/demo/A.swift", line: 1, column: 1)
        )
        let outcome = CheckOutcome(
            ruleIdentifier: "x", title: "X", status: .passed,
            violations: [v]
        )
        let out = TerminalReporter(useColour: false).render(makeResult(outcomes: [outcome]))
        // Every "word" should still appear (no truncation).
        let occurrences = out.components(separatedBy: "word").count - 1
        #expect(occurrences == 30)
    }
}
