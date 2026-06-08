# PrivacyLint — HANDOFF

_Last updated: 2026-06-08 (post PrivacyManifestValidator)_

## What this is
A Swift CLI that scans iOS/macOS Xcode projects for App Store privacy
compliance issues — "ESLint for Apple's privacy requirements". CLI first, Mac
app later. Differentiator: AI service consent detection (Nov 2025+ rule), which
no competitor checks.

## Market / competitive context (from session brief)
- ~400,000 privacy rejections/year (Apple 2024 transparency report); fastest-growing rejection category.
- Conversion model: 2% of ~150–200k unique rejected devs at £12/mo ≈ £430k ARR; 5% ≈ £1M+.
- **Main competitor: Oxbit Preflight** — native Mac app (Mar 2026), source-level scanning + local CoreML false-positive filtering, offline. Generalist (sandbox/security/localisation/privacy). Does NOT: resolve dependency trees for SDK manifests, validate `.xcprivacy` reasons vs. code, detect AI consent, or push a living rules engine. Our edge = privacy depth + monthly rule updates.
- Others (stelabouras, Wooder, techinpark, crasowas) = grep-based, stuck on May-2024 rules, unmaintained. Metadata scanners (AcceptMyApp etc.) don't read source.
- **Risk:** if the rules engine isn't maintained monthly, the tool dies like the 2024 CLIs.

## Current state — Steps 1-6 ✅ (scaffold, discovery, CLI, scanner #1, platform-aware, scanner #2)
- `5e218c3` scaffold.
- `f19e324` `ProjectDiscovery` — walks the project and classifies files. 11 tests.
- `f82620b` CLI wired to discovery — `PrivacyLintCommand` passes populated `ScanContext` to `RuleRegistry`.
- `16cb1f3 feat: implement RequiredReasonAPIScanner via SwiftSyntax AST` — first real scanner. Walks `MemberAccessExprSyntax` and `DeclReferenceExprSyntax`, indexes triggering symbols from `PrivacyLintRules.RequiredReasonAPIs`, reports `file:line:column` with ITMS-91053 messaging and actionable remediation citing approved reason codes. swift-syntax `"600.0.0"..<"604.0.0"` (resolves to 603.0.1).
- **Platform-awareness** — `ApplePlatform` enum encodes the matrix: macOS is the sole exemption from Required-Reason API. `CheckStatus { passed, failed, skippedForPlatform, notImplemented }` makes the report honest. `PlatformDetector` uses `swift package describe --type json` (separate JSON-parsing entry point — direct shell-out from `swift test` deadlocks on the SPM build lock).
- **`922f7c5 feat: implement PrivacyManifestValidator (ITMS-91053 cross-check)`** — the validator that turns code-level warnings into App-Review-grade `.error`s. Cross-references `PrivacyInfo.xcprivacy` declarations against actual usage detected by `RequiredReasonAPIScanner.detectUsage(in:)`. Matrix: declared correctly → passed; undeclared in use → ITMS-91053 error pointing at usage site; no manifest + usage → ONE summary error (not noisy per-category) listing all categories; declared but unused → dead-declaration warning; empty reasons → error; non-approved reason → warning; malformed plist → error with path; multiple manifests → union covers usage. 13 new tests cover every row. `PrivacyManifestParser` is a thin Foundation wrapper handling both XML and binary plist.
- Outstanding scanners (`.notImplemented`, visible in JSON): DependencyResolver, TrackingDomainChecker, AIConsentDetector.
- Reporters: JSON works; terminal/HTML still stubs.
- `swift build` ✅, `swift test` ✅ (48 Swift Testing + XCTest layer all pass), end-to-end smokes ✅ (no manifest → 1 summary error; wrong manifest → 2 ITMS-91053 errors + dead-decl warning; correct manifest → 0 violations).

## Project principles (load-bearing — apply to every scanner)
- **Position naturally to Apple devs in pain.** Lead with the rejection code they Googled (`ITMS-91053`, `ITMS-91061`, `Guideline 5.1.1`). Name the likely culprit dependency when we know it. Give a fix-it line, not a diagnosis. Never use "compliance" where "what App Review will block" works.
- **Consider every plausible scenario before declaring a scanner done.** Each scanner must have a scenario matrix at the top of its test file (see `RequiredReasonAPIScannerTests` and the matrix in `docs/research-swiftsyntax.md`). The matrix is the spec; if a row isn't tested, the scanner isn't done.
- **British English** in all user-facing strings.
- **No CoreData, no Firebase, SPM-only, MIT.**

## Key decisions made
- Protocol renamed `Scanner` → **`ComplianceScanner`** to avoid colliding with `Foundation.Scanner` (a real class). Important — keep this name.
- `OutputFormat` lives in Core (no ArgumentParser dep); CLI extends it to `ExpressibleByArgument`.
- `JSONReporter` is fully implemented (pure serialisation, not scanning logic); terminal/HTML reporters are placeholder stubs.
- Rule data (`PrivacyLintRules`) is plain data tables, marked "Last reviewed: 2026-06 (update monthly)". `ThirdPartySDKList` is a representative subset — complete it when building the resolver.
- Deps: swift-argument-parser ≥1.3.0, swift-syntax ≥510.0.0. macOS 13+.

## Structure
```
Sources/PrivacyLint/        CLI (PrivacyLintCommand, @main)
Sources/PrivacyLintCore/    Scanner/ Models/ Rules/ Reports/
Sources/PrivacyLintRules/   RequiredReasonAPIs, ThirdPartySDKList, AIServiceEndpoints
Tests/PrivacyLintCoreTests/ one test per scanner + registry tests
.github/workflows/ci.yml    build + test on macos-14
```

## NEXT
1. **DependencyResolver** — parse `Package.swift` + `Podfile`, cross-reference against `ThirdPartySDKList`. The "Firebase pulls in nanopb without a manifest" story is the headline. Complete the SDK list when implementing. Cross-cuts with PrivacyManifestValidator: a transitive dep missing a manifest is a separate ITMS code (`ITMS-91061`) from the undeclared-usage one (`ITMS-91053`).
2. **TrackingDomainChecker** — find network calls to tracking domains not declared in `NSPrivacyTrackingDomains`. Applies to all platforms (including macOS).
3. **AIConsentDetector** — the differentiator. Detect calls to OpenAI / Anthropic / Google AI endpoints and check for a consent-modal surface. Spec the matrix carefully.
4. **Terminal + HTML reporters** — currently stubs (`"report not yet implemented"`); JSON works.
5. **`ITMS-91053` blog post + `ITMS-91061`** — distribution play from the original brief. The validator's output is now quotable in the post (real ITMS-91053 messages, file:line, fix-it lines).

## v2 — parked features
- **`privacylint connect validate --app-id XXXX`** (HEADLINE v2 differentiator). Uses fastlane / ASC API key (Keychain entry `apple-app-store-connect`, private keys at `~/.appstoreconnect/private_keys/`) to read the privacy nutrition labels you've already declared in App Store Connect, then diffs them against what the scanner actually found in code. Nobody does declared-vs-actual validation. This is the feature that justifies the subscription and the launch post. Park until the five core scanners and reporters are live.
- **`privacylint connect replay-rejections`** — pulls last N rejections via ASC, surfaces ITMS codes, runs scanners scoped to those codes.
- **`privacylint connect check-sdk-versions`** — cross-references SDKs in your latest archive against `ThirdPartySDKList`. Catches the Firebase→nanopb case at submission time.
- `.xcodeproj` parsing for platform detection — currently we fall back to "assume all" with a one-line note. Foundation `PropertyListSerialization` can read pbxproj; do once the core scanners are stable.

## Notes / open items
- No git remote yet — commits are local only. Add a remote before relying on push.
- British English enforced in user-facing strings.
- Constraints: no Firebase, no CoreData, SPM-only, MIT licence.
