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
        // During the scaffold phase every scanner throws notImplemented, so the
        // run should complete with no outcomes rather than crashing.
        let result = RuleRegistry().run(context)
        XCTAssertTrue(result.outcomes.isEmpty)
        XCTAssertTrue(result.passed)
    }
}
