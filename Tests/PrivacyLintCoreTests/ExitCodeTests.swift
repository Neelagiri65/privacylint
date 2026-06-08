import Foundation
import Testing
@testable import PrivacyLintCore

/// Contract for CLI exit codes — the spec consumed by GitHub Actions, Xcode
/// build phases, pre-commit hooks. Any change here should be a deliberate
/// breaking change announced in release notes.
@Suite("ScanResult.exitCode — CI contract")
struct ExitCodeTests {

    private func result(with violations: [Violation]) -> ScanResult {
        let outcome = CheckOutcome(
            ruleIdentifier: "x", title: "X",
            status: violations.contains(where: { $0.severity == .error }) ? .failed : .passed,
            violations: violations
        )
        return ScanResult(projectPath: "/tmp/demo", outcomes: [outcome])
    }

    @Test func cleanRunExitsZero() {
        #expect(result(with: []).exitCode() == 0)
    }

    @Test func errorViolationExitsOne() {
        let v = Violation(ruleIdentifier: "x", severity: .error, message: "blocking")
        #expect(result(with: [v]).exitCode() == 1)
    }

    @Test func warningOnlyDefaultsToZero() {
        // Non-strict CI keeps passing on warnings — opt-in to strict mode
        // explicitly via --warnings-as-errors. Don't surprise existing
        // pipelines.
        let v = Violation(ruleIdentifier: "x", severity: .warning, message: "soft")
        #expect(result(with: [v]).exitCode() == 0)
    }

    @Test func warningsAsErrorsFlagEscalates() {
        let v = Violation(ruleIdentifier: "x", severity: .warning, message: "soft")
        #expect(result(with: [v]).exitCode(warningsAsErrors: true) == 1)
    }

    @Test func infoNeverFails() {
        let v = Violation(ruleIdentifier: "x", severity: .info, message: "fyi")
        #expect(result(with: [v]).exitCode() == 0)
        #expect(result(with: [v]).exitCode(warningsAsErrors: true) == 0)
    }

    @Test func mixedSeveritiesExitsOneIfAnyError() {
        let e = Violation(ruleIdentifier: "x", severity: .error, message: "boom")
        let w = Violation(ruleIdentifier: "x", severity: .warning, message: "soft")
        #expect(result(with: [e, w]).exitCode() == 1)
    }
}
