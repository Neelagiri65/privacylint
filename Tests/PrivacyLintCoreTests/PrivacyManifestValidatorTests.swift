import XCTest
@testable import PrivacyLintCore

final class PrivacyManifestValidatorTests: XCTestCase {
    private let context = ScanContext(projectPath: URL(fileURLWithPath: "/tmp/sample"))

    func testHasStableIdentifier() {
        XCTAssertEqual(PrivacyManifestValidator().ruleIdentifier, "privacy-manifest-validation")
    }

    func testScanIsNotYetImplemented() {
        XCTAssertThrowsError(try PrivacyManifestValidator().scan(context)) { error in
            XCTAssertEqual(error as? ScannerError, .notImplemented)
        }
    }

    func testEmptyManifestDefaults() {
        let manifest = PrivacyManifest()
        XCTAssertFalse(manifest.tracking)
        XCTAssertTrue(manifest.accessedAPITypes.isEmpty)
    }
}
