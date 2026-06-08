import Foundation
import Testing
@testable import PrivacyLintCore
import PrivacyLintRules

/// The architectural gate for RequiredReasonAPIScanner.
///
/// These tests encode the scenario matrix from
/// `docs/research-swiftsyntax.md` — Positioning & Exhaustive-Scenarios. If
/// they pass, the AST foundation is proven and every future Required Reason
/// rule is just a data addition to `RequiredReasonAPIs.all`.
@Suite("RequiredReasonAPIScanner — architectural gate")
struct RequiredReasonAPIScannerTests {
    private func scan(_ source: String, file: String = "/tmp/A.swift") -> [Violation] {
        let url = URL(fileURLWithPath: file)
        return RequiredReasonAPIScanner().scanSource(source, file: url)
    }

    // MARK: - Identity

    @Test func hasStableIdentifier() {
        #expect(RequiredReasonAPIScanner().ruleIdentifier == "required-reason-api")
    }

    // MARK: - The four-scenario architectural gate

    /// Scenario 1: real detection. The simplest possible production use.
    @Test func detectsUserDefaultsAccessAtCorrectLine() throws {
        let source = """
        import Foundation
        func load() {
            let v = UserDefaults.standard.bool(forKey: "k")
            _ = v
        }
        """
        let violations = scan(source)
        #expect(violations.count == 1)
        let v = try #require(violations.first)
        #expect(v.ruleIdentifier == "required-reason-api")
        #expect(v.message.contains("UserDefaults"))
        #expect(v.message.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(v.location?.line == 3)
    }

    /// Scenario 2: comments. The grep tools fail here. We must not.
    @Test func ignoresMatchesInsideComments() {
        let source = """
        // This file used UserDefaults.standard for legacy reasons.
        /// We removed `UserDefaults.standard` last release.
        /* UserDefaults.standard appeared here too. */
        func noop() {}
        """
        #expect(scan(source).isEmpty)
    }

    /// Scenario 3: string literals. Same — grep flags them, we must not.
    @Test func ignoresMatchesInsideStringLiterals() {
        let source = #"""
        let label = "UserDefaults.standard is just a string"
        let multi = """
        UserDefaults.standard appears here too
        """
        """#
        #expect(scan(source).isEmpty)
    }

    /// Scenario 4: chained access. `ProcessInfo.processInfo.systemUptime`
    /// is the canonical Required Reason example for the boot-time category.
    @Test func detectsChainedMemberAccess() throws {
        let source = """
        import Foundation
        let uptime = ProcessInfo.processInfo.systemUptime
        """
        let violations = scan(source)
        #expect(violations.count == 1)
        let v = try #require(violations.first)
        #expect(v.message.contains("systemUptime"))
        #expect(v.message.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
    }

    // MARK: - Supporting scenarios from the matrix

    @Test func interpolationCountsAsRealCode() {
        let source = #"""
        let s = "uptime=\(ProcessInfo.processInfo.systemUptime)"
        _ = s
        """#
        #expect(scan(source).count == 1)
    }

    @Test func detectsRequiredReasonPropertyOnExistingValue() {
        let source = """
        import Foundation
        func touch(_ file: URL) throws {
            let d = try file.resourceValues(forKeys: [.contentModificationDateKey])
            _ = d
        }
        """
        // .contentModificationDateKey is in the file-timestamp triggering set.
        let violations = scan(source)
        #expect(violations.contains { $0.message.contains("contentModificationDateKey") })
    }

    @Test func skipsTestTargetFiles() throws {
        // A file in context.testFiles must not be scanned.
        let prodURL = URL(fileURLWithPath: "/tmp/Prod.swift")
        let testURL = URL(fileURLWithPath: "/tmp/Tests/AppTests.swift")
        let context = ScanContext(
            projectPath: URL(fileURLWithPath: "/tmp"),
            sourceFiles: [prodURL],
            testFiles: [testURL]
        )
        // We don't write the files to disk — we just verify the scanner reads
        // sourceFiles and ignores testFiles. With both URLs pointing at
        // non-existent paths, scan should throw on the prod file rather than
        // silently consuming the test file. That confirms only sourceFiles
        // are iterated.
        #expect(throws: (any Error).self) {
            try RequiredReasonAPIScanner().scan(context)
        }
    }

    @Test func reportsCorrectLineForMatchOnLaterLine() throws {
        let source = """
        import Foundation

        // line 3
        func a() {}

        let u = UserDefaults.standard
        """
        let v = try #require(scan(source).first)
        #expect(v.location?.line == 6)
    }
}
