import Foundation
import Testing
@testable import PrivacyLintCore
import PrivacyLintRules

/// The architectural gate for PrivacyManifestValidator.
///
/// Scenario matrix — each row maps to at least one test below.
///
/// | # | Scenario                                                         | Expected outcome                              |
/// | - | ---------------------------------------------------------------- | --------------------------------------------- |
/// | 1 | Code uses UserDefaults + manifest declares CA92.1                | passed (no violations)                        |
/// | 2 | Code uses UserDefaults + manifest exists but no UserDefaults entry | .error ITMS-91053 (undeclared category)     |
/// | 3 | Code uses UserDefaults + no PrivacyInfo.xcprivacy at all         | .error ITMS-91053 (missing manifest) — ONE   |
/// | 4 | Manifest declares UserDefaults; code never uses it               | .warning (dead declaration)                   |
/// | 5 | Manifest entry has empty reasons array                           | .error                                        |
/// | 6 | Manifest entry has a reason code not in Apple's approved list    | .warning                                      |
/// | 7 | Manifest file is malformed plist                                 | .error                                        |
/// | 8 | Two manifests; union covers usage                                | passed                                        |
/// | 9 | macOS-only project                                               | skippedForPlatform (platform-awareness)       |
/// |10 | No source files, no manifest                                     | passed                                        |
@Suite("PrivacyManifestValidator — architectural gate")
struct PrivacyManifestValidatorTests {

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-pmv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSource(_ text: String, named name: String = "App.swift", in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeManifest(
        accessedAPITypes: [(category: String, reasons: [String])],
        named name: String = "PrivacyInfo.xcprivacy",
        in dir: URL
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dict: [String: Any] = [
            "NSPrivacyTracking": false,
            "NSPrivacyAccessedAPITypes": accessedAPITypes.map { entry in
                [
                    "NSPrivacyAccessedAPIType": entry.category,
                    "NSPrivacyAccessedAPITypeReasons": entry.reasons
                ] as [String: Any]
            }
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
        try data.write(to: url)
        return url
    }

    private let userDefaultsSource = """
    import Foundation
    let v = UserDefaults.standard.bool(forKey: "k")
    """

    // MARK: - Identity

    @Test func hasStableIdentifier() {
        #expect(PrivacyManifestValidator().ruleIdentifier == "privacy-manifest-validation")
    }

    @Test func macOSIsExempt() {
        let validator = PrivacyManifestValidator()
        #expect(!validator.applicablePlatforms.contains(.macOS))
        #expect(validator.applicablePlatforms.contains(.iOS))
    }

    // MARK: - Scenario 1: declared correctly

    @Test func declaredCategoryWithValidReasonPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource(userDefaultsSource, in: dir)
        let manifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategoryUserDefaults", reasons: ["CA92.1"])],
            in: dir
        )
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [manifest], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        #expect(violations.isEmpty, "Unexpected violations: \(violations.map(\.message))")
    }

    // MARK: - Scenario 2: undeclared category

    @Test func undeclaredCategoryInUseProducesITMS91053Error() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource(userDefaultsSource, in: dir)
        let manifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategoryFileTimestamp", reasons: ["DDA9.1"])],
            in: dir
        )
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [manifest], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        let errors = violations.filter { $0.severity == .error }
        let undeclared = errors.first { $0.message.contains("NSPrivacyAccessedAPICategoryUserDefaults") }
        let v = try #require(undeclared)
        #expect(v.message.contains("ITMS-91053"))
        #expect(v.location?.file.hasSuffix("App.swift") == true)
    }

    // MARK: - Scenario 3: no manifest at all

    @Test func usageWithNoManifestProducesOneSummaryError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        let v = UserDefaults.standard.bool(forKey: "k")
        let u = ProcessInfo.processInfo.systemUptime
        """, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        #expect(violations.count == 1)
        let v = try #require(violations.first)
        #expect(v.severity == .error)
        #expect(v.message.contains("no PrivacyInfo.xcprivacy"))
        #expect(v.message.contains("ITMS-91053"))
        #expect(v.message.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(v.message.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
    }

    // MARK: - Scenario 4: dead declaration

    @Test func declaredButUnusedCategoryWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("import Foundation\nlet x = 1", in: dir)
        let manifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategoryUserDefaults", reasons: ["CA92.1"])],
            in: dir
        )
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [manifest], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        let dead = violations.first { $0.message.contains("no code uses it") }
        let v = try #require(dead)
        #expect(v.severity == .warning)
    }

    // MARK: - Scenario 5: empty reasons

    @Test func entryWithEmptyReasonsIsBlockingError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource(userDefaultsSource, in: dir)
        let manifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategoryUserDefaults", reasons: [])],
            in: dir
        )
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [manifest], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        let v = try #require(violations.first { $0.message.contains("no reasons") })
        #expect(v.severity == .error)
    }

    // MARK: - Scenario 6: non-approved reason

    @Test func nonApprovedReasonCodeWarns() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource(userDefaultsSource, in: dir)
        let manifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategoryUserDefaults", reasons: ["XYZ.99"])],
            in: dir
        )
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [manifest], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        let v = try #require(violations.first { $0.message.contains("XYZ.99") })
        #expect(v.severity == .warning)
        #expect(v.message.contains("not in Apple"))
    }

    // MARK: - Scenario 7: malformed plist

    @Test func malformedManifestProducesError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = dir.appendingPathComponent("PrivacyInfo.xcprivacy")
        try Data("this is not a plist".utf8).write(to: manifest)
        let source = try writeSource(userDefaultsSource, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], privacyManifests: [manifest], platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        let parseError = violations.first { $0.message.contains("Failed to parse") }
        #expect(parseError?.severity == .error)
    }

    // MARK: - Scenario 8: two manifests, union covers

    @Test func twoManifestsUnionCoversUsage() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource("""
        import Foundation
        let v = UserDefaults.standard.bool(forKey: "k")
        let u = ProcessInfo.processInfo.systemUptime
        """, in: dir)
        let appManifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategoryUserDefaults", reasons: ["CA92.1"])],
            named: "PrivacyInfo.xcprivacy", in: dir
        )
        let frameworkManifest = try writeManifest(
            accessedAPITypes: [(category: "NSPrivacyAccessedAPICategorySystemBootTime", reasons: ["35F9.1"])],
            named: "Framework.xcprivacy", in: dir
        )
        let context = ScanContext(
            projectPath: dir,
            sourceFiles: [source],
            privacyManifests: [appManifest, frameworkManifest],
            platforms: [.iOS]
        )
        let violations = try PrivacyManifestValidator().scan(context)
        #expect(violations.isEmpty, "Unexpected violations: \(violations.map(\.message))")
    }

    // MARK: - Scenario 9: macOS-only

    @Test func macOSOnlyProjectSkipsValidatorEntirely() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try writeSource(userDefaultsSource, in: dir)
        let context = ScanContext(projectPath: dir, sourceFiles: [source], platforms: [.macOS])
        let result = RuleRegistry().run(context)
        let pmv = result.outcomes.first { $0.ruleIdentifier == "privacy-manifest-validation" }
        #expect(pmv?.status == .skippedForPlatform)
        #expect(pmv?.violations.isEmpty == true)
    }

    // MARK: - Scenario 10: nothing to validate

    @Test func noSourceAndNoManifestPasses() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = ScanContext(projectPath: dir, platforms: [.iOS])
        let violations = try PrivacyManifestValidator().scan(context)
        #expect(violations.isEmpty)
    }

    // MARK: - Parser unit coverage

    @Test func parserReadsAccessedAPITypes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeManifest(
            accessedAPITypes: [
                (category: "NSPrivacyAccessedAPICategoryUserDefaults", reasons: ["CA92.1"]),
                (category: "NSPrivacyAccessedAPICategorySystemBootTime", reasons: ["35F9.1", "8FFB.1"])
            ],
            in: dir
        )
        let manifest = try PrivacyManifestParser.parse(at: url)
        #expect(manifest.accessedAPITypes.count == 2)
        #expect(manifest.accessedAPITypes[0].apiCategory == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(manifest.accessedAPITypes[1].reasons == ["35F9.1", "8FFB.1"])
    }
}
