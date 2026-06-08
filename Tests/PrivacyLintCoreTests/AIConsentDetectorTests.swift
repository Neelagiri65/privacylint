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

    func testRegistrySkipsUnimplementedScanners() {
        // Scanners that still throw notImplemented are skipped; implemented
        // ones (currently just RequiredReasonAPIScanner) produce an outcome.
        // An empty ScanContext gives the implemented scanner zero files to
        // walk, so it produces one passing outcome with no violations.
        let result = RuleRegistry().run(context)
        XCTAssertEqual(result.outcomes.count, 1)
        XCTAssertEqual(result.outcomes.first?.ruleIdentifier, "required-reason-api")
        XCTAssertTrue(result.passed)
    }
}
