import XCTest
@testable import PrivacyLintCore

final class AIConsentDetectorTests: XCTestCase {
    private let context = ScanContext(projectPath: URL(fileURLWithPath: "/tmp/sample"))

    func testHasStableIdentifier() {
        XCTAssertEqual(AIConsentDetector().ruleIdentifier, "ai-consent")
    }

    func testScanIsNotYetImplemented() {
        XCTAssertThrowsError(try AIConsentDetector().scan(context)) { error in
            XCTAssertEqual(error as? ScannerError, .notImplemented)
        }
    }

    func testRegistryRegistersEveryScanner() {
        XCTAssertEqual(RuleRegistry.allScanners.count, 5)
    }

    func testRegistryReportsEveryScannerStatus() {
        // Honesty over invisibility: every registered scanner now appears in
        // the result with its true status. The four still-scaffolded ones
        // are .notImplemented; the implemented one is .passed (no files to
        // walk, no violations).
        let result = RuleRegistry().run(context)
        XCTAssertEqual(result.outcomes.count, 5)
        let statuses = Dictionary(uniqueKeysWithValues: result.outcomes.map { ($0.ruleIdentifier, $0.status) })
        XCTAssertEqual(statuses["required-reason-api"], .passed)
        XCTAssertEqual(statuses["ai-consent"], .notImplemented)
        XCTAssertEqual(statuses["third-party-sdk-manifest"], .notImplemented)
        XCTAssertTrue(result.passed) // notImplemented isn't a failure
    }
}
