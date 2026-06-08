# Research — SwiftSyntax for PrivacyLint's RequiredReasonAPIScanner

_Date: 2026-06-08. Status: ready for review. No code written yet._

## Step 1 — What I'm about to build
I am about to build a `RequiredReasonAPIScanner` that uses **SwiftSyntax + SwiftParser AST-level analysis** (not regex/grep) to detect every use of Apple's Required-Reason APIs (e.g. `UserDefaults.standard`, `FileManager.default.attributesOfItem`, `ProcessInfo.processInfo.systemUptime`, `NSURL.fileSize`, etc.) in an iOS/macOS project's Swift source — reporting `file:line:column`, the API category (e.g. `NSPrivacyAccessedAPICategoryFileTimestamp`), and skipping comments, doc-comments, and test targets — so that PrivacyLint can validate the project's `PrivacyInfo.xcprivacy` against actual code usage.

## Step 2 — Existing solutions
Already audited in the previous session (recap):
- **stelabouras / Wooder / techinpark / crasowas** — all grep/regex, all unmaintained for 2025-2026 rules. Explicitly warn "don't rely on it." No AST.
- **Privado.ai** — enterprise platform, broader privacy governance, not source-level for indie devs.
- **App Privacy Manifest Fixer** (Apr 2025) — emerging, focus unclear.
- **Oxbit Preflight** (Mar 2026) — native Mac app, source-level pattern matching with CoreML false-positive filtering. Generalist (sandbox/security/localisation/privacy). Per its App Store listing: does NOT resolve dependency trees, does NOT validate `.xcprivacy` reasons vs code, does NOT detect AI consent. Real competitor; our edge = depth + monthly rule updates.
- **No existing tool uses SwiftSyntax for privacy compliance.** This is the moat — the AST work is genuinely hard, which is exactly why nothing solves it well today (per the report.docx ranking, pain point #3, "wide open").

What we learn from their approach:
- Grep loses on **comments, dead code, test targets, string literals** — the AST is the only way to get false-positive rates low enough to ship.
- Snapshot tools die when Apple ships new rules. The rules engine (PrivacyLintRules module already scaffolded) must be the long-term moat.

## Step 3 — Architectural constraints
| Constraint                                                    | Approach satisfies?                                                                                                                              |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| SPM-only, macOS 13+, no Foundation-on-Linux assumptions       | ✅ swift-syntax is pure-Swift SPM, runs on macOS 13+                                                                                              |
| MIT-compatible licence                                        | ✅ swift-syntax is Apache-2.0 (compatible with MIT distribution)                                                                                  |
| Swift 6.3 / Xcode 26 toolchain                                | ⚠️ See **Version pinning** below — 510.0.0 (currently in Package.swift) is too old; bump to 603 stable                                            |
| AST-level (not grep) — must understand comments / test code   | ✅ `SyntaxVisitor` with `viewMode: .sourceAccurate` skips trivia; we already split test files in `ScanContext.testFiles`                          |
| Pipeline must run end-to-end fast enough for thousands of files | ✅ See **Cost** below — full-file parse is fast enough; no need for incremental parsing in v1                                                     |
| Architectural test before build (ContextKey lesson)            | Will be the first test in `RequiredReasonAPIScannerTests`: feed a string containing a match, assert exactly one violation with correct file:line |

## Step 4 — Pitfalls (from web + vault failures)
**SwiftSyntax-specific gotchas:**
1. **Version-toolchain coupling.** swift-syntax major version follows Swift minor version: `509`→Swift 5.9, `600`→6.0, `601`→6.1, `602`→6.2, `603`→6.3. SPM cannot resolve two majors of the same dep simultaneously; pinning matters. (Confirmed via [Swift Forums thread][forum-multi-version] and the releases list.)
2. **NSHipster's article is stale.** It references SwiftSyntax delegating to `swiftc` via temp files. That was the libSyntax era. Modern swift-syntax (≥ 5XX) ships a **pure-Swift parser** (`SwiftParser`); no `swiftc`, no temp files, no system calls. ([SwiftParser docs][parser-docs])
3. **Macros (`@Macro`, `#externalMacro`)** are just attributed declarations in the syntax tree — they parse fine. We don't expand them; we treat the macro-call site as the source. Acceptable for v1 since required-reason APIs are stdlib/system, not macro-emitted.
4. **Conditional compilation (`#if DEBUG`).** `Parser.parse(source:)` parses both branches into `IfConfigDeclSyntax`. A naive walker will flag a Required-Reason API call that lives only in `#if DEBUG`. For v1: flag it (developers usually want to know). Future: an option `--exclude-ifconfig-branches DEBUG`.
5. **String interpolation** (`"value=\(UserDefaults.standard.bool(...))"`) is a real expression in the tree — `ExpressionSegmentSyntax`. Walker will catch it correctly; no special handling needed.
6. **Resilient parser.** `Parser.parse` *never throws*. Errors are encoded as `UnexpectedNodesSyntax` and `MissingTokenSyntax` in the tree. The scanner should still walk; we just won't emit violations on `UnexpectedNodesSyntax` branches. For v1, ignore — if a file doesn't compile in Xcode, it's not the scanner's job.
7. **Objective-C files.** SwiftSyntax is Swift-only. `ScanContext.objcFiles` is collected but won't be AST-parsed. Document this limitation; v2 may add a regex sidecar for `.m` files.

**Vault failures cross-checked:**
- `gstack-failure.md` — installed framework wholesale. ✅ We're pulling only `SwiftSyntax` + `SwiftParser` modules, not the whole macro stack (we don't need `SwiftSyntaxMacros`, `SwiftCompilerPlugin`, etc.).
- `contextkey-cloud-api-flaw.md` — architectural constraint test before code. ✅ Step 5 below.
- `marketplace-double-rejection.md` — fix everything, not just cited items. ✅ Scanner will cover all 6 required-reason API *categories* in one pass, not just one symbol.

## Step 5 — How I'll know it works
The **architectural constraint test** (must pass before any other scanner code is added):

```swift
@Test func detectsUserDefaultsAccessAtCorrectLineColumn() throws {
    let source = """
    import Foundation
    func load() {
        let v = UserDefaults.standard.bool(forKey: "k")
        _ = v
    }
    """
    let violations = try RequiredReasonAPIScanner().scan(
        sources: [(path: URL(fileURLWithPath: "/tmp/A.swift"), source: source)]
    )
    #expect(violations.count == 1)
    #expect(violations[0].category == "NSPrivacyAccessedAPICategoryUserDefaults")
    #expect(violations[0].file.lastPathComponent == "A.swift")
    #expect(violations[0].line == 3)
}
```

Plus negatives that grep would get wrong:
```swift
@Test func ignoresMatchesInsideComments() throws {
    let source = """
    // This file uses UserDefaults.standard for legacy reasons
    /// We removed `UserDefaults.standard` last release
    let s = "UserDefaults.standard is a string literal here"
    """
    #expect(try RequiredReasonAPIScanner().scan(sources: [...]).isEmpty)
}

@Test func detectsChainedMemberAccess() throws {
    // ProcessInfo.processInfo.systemUptime — three-deep MemberAccessExpr
}

@Test func skipsTestTargets() throws {
    // sources in ScanContext.testFiles must NOT be scanned
}
```

Success = all four tests pass + scanner runs over the PrivacyLint repo itself (~30 Swift files) in < 1 second.
Failure = any grep-class false positive (string literal, comment) or missed chained access.

## Recommendations (the actionable part)

### 1. Version pinning — bump from `>= 510.0.0` to `from: 600.0.0`, allow up to `< 604.0.0`
Current `Package.swift` pins `swift-syntax >= 510.0.0`. That's Swift 5.10 (Mar 2024). We're on Swift 6.3 (Xcode 26). Recommendation:

```swift
.package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"604.0.0"),
```

- `600` is the lowest sane floor for Swift 6.x runtime guarantees.
- `<604` excludes the 604 prereleases (Jun 2026) until they go stable.
- Latest stable is **603.0.1** (Apr 2026) — that's what SPM will resolve.

### 2. Module subset to import
Just two:
```swift
.product(name: "SwiftSyntax",  package: "swift-syntax"),
.product(name: "SwiftParser",  package: "swift-syntax"),
```
Skip `SwiftSyntaxBuilder`, `SwiftSyntaxMacros`, `SwiftCompilerPlugin`, `SwiftOperators` — we read code, we don't emit it.

### 3. Parsing API (confirmed from source)
```swift
import SwiftParser
import SwiftSyntax

let tree: SourceFileSyntax = Parser.parse(source: sourceString)
// Parser.parse(source:) takes String. There is also Parser.parse(source: UnsafeBufferPointer<UInt8>) for bytes.
// Never throws — recovers via UnexpectedNodesSyntax / MissingTokenSyntax.
```

### 4. Walker pattern
Subclass `SyntaxVisitor`, override `visit(_:)` for the node types we care about, return `.visitChildren` to keep descending or `.skipChildren` to short-circuit:

```swift
final class RequiredReasonVisitor: SyntaxVisitor {
    var hits: [Hit] = []
    let converter: SourceLocationConverter   // built from the SourceFileSyntax once
    let rules: [APIRule]                     // from PrivacyLintRules

    init(file: URL, tree: SourceFileSyntax, rules: [APIRule]) {
        self.converter = SourceLocationConverter(fileName: file.path, tree: tree)
        self.rules = rules
        super.init(viewMode: .sourceAccurate)   // skips invalid/missing nodes
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // e.g. `UserDefaults.standard`:
        //   node.base is DeclReferenceExprSyntax(baseName: "UserDefaults")
        //   node.declName.baseName.text == "standard"
        if let base = node.base?.as(DeclReferenceExprSyntax.self),
           let rule = rules.first(where: { $0.matches(base: base.baseName.text,
                                                     member: node.declName.baseName.text) }) {
            let loc = node.startLocation(converter: converter)
            hits.append(Hit(rule: rule, file: file, line: loc.line, column: loc.column))
        }
        return .visitChildren
    }
}
```

For chained access (`ProcessInfo.processInfo.systemUptime`) the outer node's `base` is itself a `MemberAccessExprSyntax`. Walk it: each level fires its own `visit(_:)` call, so the rule definition just needs to express "base = `ProcessInfo.processInfo`, member = `systemUptime`". A small helper that flattens chained MemberAccess into a dotted string keeps the rule data clean:
```swift
extension MemberAccessExprSyntax {
    func dottedPath() -> String { /* "ProcessInfo.processInfo.systemUptime" */ }
}
```

### 5. Source location reporting
```swift
let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
let loc = anyNode.startLocation(converter: converter)   // 1-based line + column
```
Both `line` and `column` are 1-based — matches Xcode's diagnostic format.

### 6. Skipping comments / string literals
Free with `viewMode: .sourceAccurate`. Comments live in `Trivia`, not in the syntax-node stream that `SyntaxVisitor.visit` dispatches over. String literals are `StringLiteralExprSyntax`, distinct from `MemberAccessExprSyntax` — our visit only fires on real expressions.

### 7. Cost / throughput
- Pure-Swift parser is roughly on par with the old C++ parser (per the SwiftParser docs). In practice: a 1 KB Swift file parses in **single-digit milliseconds**; a 10 KLOC file in tens of ms.
- For thousands of files, full-file parsing is fine. We can parallelise per-file with `TaskGroup` since each parse is independent and the visitor instance is per-file.
- **No need for incremental parsing in v1.** Revisit if `swift test` over a 50K-file monorepo exceeds 10s wall-clock.

### 8. Things we are *not* doing in v1
- No macro expansion (treat call site as source).
- No semantic / type resolution (SwiftSyntax can't do this — that's `SourceKit`). This means we cannot tell `let x: UserDefaults = ...; x.bool(...)` is a UserDefaults access without the type info. Acceptable: required-reason APIs are typically called as `UserDefaults.standard.bool(...)` or `FileManager.default.attributesOfItem(...)` — the static-syntax pattern catches the documented usage form.
- No Objective-C parsing.

## Positioning & exhaustive-scenarios principle (load-bearing for every scanner)

**Position naturally to the Apple developer's actual pain.** Every error
message, README line, and CLI output must read like it was written by
someone who has been rejected by App Review and knows the panic of opening
the `ITMS-XXXXX` email. Concretely:

- Lead with the **rejection code** developers Google. `ITMS-91053`,
  `ITMS-91061`, `Guideline 5.1.1`. These are the strings in their inbox.
- Name the **likely culprit dependency** when we can (Firebase → nanopb).
- Give a **fix-it line**, not just a diagnosis. "Add reason `CA92.1` for
  `NSPrivacyAccessedAPICategoryUserDefaults` in your `PrivacyInfo.xcprivacy`."
- British English in user-facing strings (project convention).
- Never use the word "compliance" where "what App Review will block" works.

**Consider every plausible scenario before declaring a scanner done.** Before
landing any scanner, list its scenario matrix and walk through each one. The
RequiredReasonAPI matrix:

| Scenario                                                              | Expected behaviour                          |
| --------------------------------------------------------------------- | ------------------------------------------- |
| `UserDefaults.standard.bool(forKey:)` in production code              | Flag (1 violation)                          |
| `let d = UserDefaults()`                                              | Flag                                        |
| `// uses UserDefaults.standard`                                       | Skip (comment)                              |
| `/// docs mentioning UserDefaults.standard`                           | Skip (doc-comment)                          |
| `let s = "UserDefaults.standard is in this string"`                   | Skip (string literal)                       |
| `"text \(UserDefaults.standard.bool(forKey:"k"))"`                    | Flag (interpolation IS code)                |
| `file.modificationDate` (Required Reason property on existing var)    | Flag                                        |
| `ProcessInfo.processInfo.systemUptime` (chained, 3 deep)              | Flag once, pointing at `systemUptime`       |
| Same call in a `*Tests`/`*UITests` directory                          | Skip (test target)                          |
| Same call in `.build/`, `Pods/`, `Carthage/`, `DerivedData/`          | Skip (excluded by ProjectDiscovery)         |
| `#if DEBUG` branch only                                               | Flag (v1) — flag noted in README            |
| Inside a `@MainActor`/`@available` attributed declaration             | Flag (attributes don't change call site)    |
| Same symbol name used as a parameter label (`foo(modificationDate:)`) | Skip (it's a label, not a member access)    |
| Same symbol name on an unrelated user type (`MyModel.creationDate`)   | Flag (v1 false positive, documented)        |
| File that fails to parse                                              | Best-effort: skip unrecoverable nodes       |
| Custom `UserDefaults` typealias                                       | Flag (treat as the symbol — best effort)    |
| Obj-C `.m` file uses `NSFileManager`                                  | Miss (out of scope v1, README disclosed)    |

Whenever a new scanner is added, write its own matrix at the top of its test
file. The matrix is the spec.

## Step 6 — Confirm and proceed
Awaiting your sign-off on:
1. **Version bump** in `Package.swift` from `>= 510.0.0` to `"600.0.0"..<"604.0.0"`.
2. **Scanner shape** sketched in §4 (subclass `SyntaxVisitor`, per-file converter, dotted-path matcher against `PrivacyLintRules.RequiredReasonAPIs`).
3. **Architectural test** in §5 as the first test written, before any other scanner code.
4. **Out-of-scope for v1**: macros, type resolution, Obj-C, incremental parsing.

If yes, next move is: edit `Package.swift`, write `RequiredReasonAPIScannerTests` with the four tests, then implement the scanner until they pass.

---
## Sources
- [swift-syntax README (main)](https://github.com/swiftlang/swift-syntax/blob/main/README.md)
- [swift-syntax releases](https://github.com/swiftlang/swift-syntax/releases) — latest stable 603.0.1, prereleases for 604.0.0
- [`SwiftParser.md` quickstart][parser-docs]
- [`SyntaxVisitor.swift` (generated source)](https://raw.githubusercontent.com/swiftlang/swift-syntax/main/Sources/SwiftSyntax/generated/SyntaxVisitor.swift) — confirmed `open class SyntaxVisitor`, `SyntaxVisitorContinueKind { visitChildren, skipChildren }`, override `visit(_ node: <Type>) -> SyntaxVisitorContinueKind`
- [`SourceLocation.swift`](https://raw.githubusercontent.com/swiftlang/swift-syntax/main/Sources/SwiftSyntax/SourceLocation.swift) — `SourceLocationConverter(fileName:tree:)`, `SyntaxProtocol.startLocation(converter:afterLeadingTrivia:)`
- [`MemberAccessExprSyntax` definition](https://raw.githubusercontent.com/swiftlang/swift-syntax/main/Sources/SwiftSyntax/generated/syntaxNodes/SyntaxNodesJKLMN.swift) — `base: ExprSyntax?`, `period: TokenSyntax`, `declName: DeclReferenceExprSyntax`
- [Swift Forums — multi-version support][forum-multi-version]
- NSHipster article — *stale*, kept here as a known-outdated reference: https://nshipster.com/swiftsyntax/
- avanderlee.com — https://www.avanderlee.com/swift/swiftsyntax-parse-and-generate-swift-source-code/
- A New Swift Parser for SwiftSyntax (Swift Forums, 2022) — https://forums.swift.org/t/a-new-swift-parser-for-swiftsyntax/59813

[parser-docs]: https://github.com/swiftlang/swift-syntax/blob/main/Sources/SwiftParser/SwiftParser.docc/SwiftParser.md
[forum-multi-version]: https://forums.swift.org/t/best-way-to-support-multiple-swiftsyntax-versions/86961
