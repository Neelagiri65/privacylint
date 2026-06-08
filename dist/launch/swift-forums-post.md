## Title

**PrivacyLint v0.1.0 — SwiftSyntax-based scanner for App Store privacy rejections (ITMS-91053, ITMS-91061, tracking domains, AI consent)**

## Category

`Related Projects` (or `Community Showcase`).

## Body

Hi all,

Sharing PrivacyLint — a Swift CLI I built using SwiftSyntax to catch the privacy-related App Store rejection codes (ITMS-91053 "Missing API declaration", ITMS-91061 "third-party SDK missing privacy manifest") and a couple of newer rules App Review enforces but doesn't have explicit ITMS codes for yet (undeclared tracking domains, AI service calls without consent surfaces).

A few notes the Swift-tooling-focused crowd here might care about:

**Architecture.** Five independent scanners conforming to a `ComplianceScanner` protocol, each with its own scenario matrix encoded as the test gate. Two AST visitors per file at most (Required-Reason API and tracking-domain checkers). Platform-aware via `Set<ApplePlatform>` threaded through `ScanContext` — macOS targets correctly skip the Required-Reason section, which is genuinely exempt.

**SwiftSyntax version pinning.** Dep range `"600.0.0"..<"604.0.0"`, currently resolving to 603.0.1 (Swift 6.3). Originally pinned at `>= 510.0.0` and that turned out to be the wrong floor for the 6.x runtime — wrote a [research note](https://github.com/Neelagiri65/privacylint/blob/master/docs/research-swiftsyntax.md) with the version-toolchain mapping and the parsing/visitor patterns we ended up using if anyone's evaluating swift-syntax for similar tooling.

**Reporter.** Honest `CheckStatus { passed, failed, skippedForPlatform, notImplemented }` so the JSON output lists every registered scanner with its true state — no silent drops. Terminal reporter does ANSI auto-detect via `isatty(fileno(stdout))`, `--no-color` for explicit override.

**Smoke-tested on IceCubesApp** — found a missing `PrivacyInfo.xcprivacy` (would be an ITMS-91053 on next submission) and 19 file:line-pinned Required-Reason usages. Triaged 14 down to SwiftData `@Model` property-name false positives; the 2 real `UserDefaults` ones went into a [PR](https://github.com/Dimillian/IceCubesApp/pull/2471).

**Install:**
```bash
brew tap Neelagiri65/privacylint
brew install privacylint
```

Source (MIT): https://github.com/Neelagiri65/privacylint

Happy to dig into the SwiftSyntax-specific bits — the `MemberAccessExprSyntax` vs `DeclReferenceExprSyntax` overlap for catching both `UserDefaults.standard` and `file.modificationDate`, the camelCase splitter for the AI-consent heuristic, the SPM-build-lock deadlock when calling `swift package describe` reentrantly from tests, etc.
