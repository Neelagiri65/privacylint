import XCTest
@testable import PrivacyLintCore

final class RequiredReasonAPIScannerTests: XCTestCase {
    private let context = ScanContext(projectPath: URL(fileURLWithPath: "/tmp/sample"))

    func testHasStableIdentifier() {
        XCTAssertEqual(RequiredReasonAPIScanner().ruleIdentifier, "required-reason-api")
    }

    func testScanIsNotYetImplemented() {
        XCTAssertThrowsError(try RequiredReasonAPIScanner().scan(context)) { error in
            XCTAssertEqual(error as? ScannerError, .notImplemented)
        }
    }
}
