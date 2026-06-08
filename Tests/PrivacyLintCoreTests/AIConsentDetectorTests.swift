import XCTest
@testable import PrivacyLintCore

/// Registry-level tests for the full scanner set. The architectural matrix
/// for AIConsentDetector lives in `AIConsentDetectorMatrixTests.swift`.
final class AIConsentDetectorTests: XCTestCase {
    private let context = ScanContext(projectPath: URL(fileURLWithPath: "/tmp/sample"))

    func testHasStableIdentifier() {
        XCTAssertEqual(AIConsentDetector().ruleIdentifier, "ai-consent")
    }

    func testRegistryRegistersEveryScanner() {
        XCTAssertEqual(RuleRegistry.allScanners.count, 5)
    }

    func testRegistryReportsEveryScannerStatus() {
        // All 5 scanners are now implemented — every outcome should be
        // .passed against an empty context (no source files, no manifests,
        // no lockfiles → nothing to flag).
        let result = RuleRegistry().run(context)
        XCTAssertEqual(result.outcomes.count, 5)
        let statuses = Dictionary(uniqueKeysWithValues: result.outcomes.map { ($0.ruleIdentifier, $0.status) })
        XCTAssertEqual(statuses["required-reason-api"], .passed)
        XCTAssertEqual(statuses["privacy-manifest-validation"], .passed)
        XCTAssertEqual(statuses["third-party-sdk-manifest"], .passed)
        XCTAssertEqual(statuses["tracking-domain-declaration"], .passed)
        XCTAssertEqual(statuses["ai-consent"], .passed)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.outcomes.filter { $0.status == .notImplemented }.count, 0)
    }
}
