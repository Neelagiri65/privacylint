import XCTest
@testable import PrivacyLintCore

final class DependencyResolverTests: XCTestCase {
    private let context = ScanContext(projectPath: URL(fileURLWithPath: "/tmp/sample"))

    func testHasStableIdentifier() {
        XCTAssertEqual(DependencyResolver().ruleIdentifier, "third-party-sdk-manifest")
    }

    func testScanIsNotYetImplemented() {
        XCTAssertThrowsError(try DependencyResolver().scan(context)) { error in
            XCTAssertEqual(error as? ScannerError, .notImplemented)
        }
    }
}
