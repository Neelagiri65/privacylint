# PrivacyLint — HANDOFF

_Last updated: 2026-06-08 (post DependencyResolver)_

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

## Current state — Steps 1-7 ✅ (scaffold, discovery, CLI, scanner #1, platform-aware, scanner #2, scanner #3)
- `5e218c3` scaffold.
- `f19e324` `ProjectDiscovery` — walks the project and classifies files. 11 tests.
- `f82620b` CLI wired to discovery — `PrivacyLintCommand` passes populated `ScanContext` to `RuleRegistry`.
- `16cb1f3 feat: implement RequiredReasonAPIScanner via SwiftSyntax AST` — first real scanner. Walks `MemberAccessExprSyntax` and `DeclReferenceExprSyntax`, indexes triggering symbols from `PrivacyLintRules.RequiredReasonAPIs`, reports `file:line:column` with ITMS-91053 messaging and actionable remediation citing approved reason codes. swift-syntax `"600.0.0"..<"604.0.0"` (resolves to 603.0.1).
- **Platform-awareness** — `ApplePlatform` enum encodes the matrix: macOS is the sole exemption from Required-Reason API. `CheckStatus { passed, failed, skippedForPlatform, notImplemented }` makes the report honest. `PlatformDetector` uses `swift package describe --type json` (separate JSON-parsing entry point — direct shell-out from `swift test` deadlocks on the SPM build lock).
- `922f7c5 feat: implement PrivacyManifestValidator (ITMS-91053 cross-check)` — turns code-level warnings into App Review `.error`s. Cross-references `PrivacyInfo.xcprivacy` against `RequiredReasonAPIScanner.detectUsage(in:)`. 13-row scenario matrix in tests. `PrivacyManifestParser` is a thin Foundation wrapper.
- **`341ac94 feat: implement DependencyResolver (ITMS-91061 / Firebase→nanopb)`** — reads `Package.resolved` and `Podfile.lock`, cross-references each (transitive) dep against `ThirdPartySDKList`, checks the local checkout for `PrivacyInfo.xcprivacy`. Headline rejection caught: Firebase silent (has manifest), transitive nanopb flagged as ITMS-91061 (no manifest). applicablePlatforms = ALL (the SDK-manifest requirement applies on every distributed platform, including macOS — unlike Required-Reason API). 12-row scenario matrix in tests. SDK matcher normalises identities (strips `-ios-sdk`, `-ios-spm`, `-ios`, `-cocoa` but NOT `-swift` since names like `RealmSwift`/`RxSwift` embed it meaningfully).
- Outstanding scanners (`.notImplemented`, visible in JSON): TrackingDomainChecker, AIConsentDetector.
- Reporters: JSON works; terminal/HTML still stubs.
- `swift build` ✅, `swift test` ✅ (64 Swift Testing + XCTest layer all pass), end-to-end smoke at `/tmp/pl-firebase` confirms the Firebase→nanopb story works.

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
1. **TrackingDomainChecker** — find network calls to tracking domains not declared in `NSPrivacyTrackingDomains`. Applies to all platforms (including macOS). Source-level AST detection: `URLRequest(url: URL(string: "https://tracker.com/...")?)`, `URLSession.shared.dataTask(...)`, etc. The tracking-domain rule data should be a known-tracker list (CommonCrawl / EasyList style); seed with a representative set, refresh monthly.
2. **AIConsentDetector** — the differentiator. Detect HTTP calls to OpenAI / Anthropic / Google AI / Cohere / Mistral endpoints and check whether a consent-modal surface is present in code. Mandatory since Nov 2025. Spec the matrix carefully — false positives here erode trust fastest.
3. **Terminal + HTML reporters** — currently stubs (`"report not yet implemented"`); JSON works.
4. **`ITMS-91053` + `ITMS-91061` blog posts** — both validators now produce quotable output with file:line + fix-it lines. Distribution play from the original brief.

## Distribution / community notes
- **`ITMS-91061` blog post** — include a "report a missing SDK match" link (GitHub issue template). The SDK matcher's normalisation rules (`-ios-sdk` strip, no `-swift` strip) will silently miss new naming conventions. Crowdsourced QA from rejected developers keeps the list accurate; we don't have to audit every new Pod ourselves.

## v2 — parked features
- **`privacylint connect validate --app-id XXXX`** (HEADLINE v2 differentiator). Uses fastlane / ASC API key (Keychain entry `apple-app-store-connect`, private keys at `~/.appstoreconnect/private_keys/`) to read the privacy nutrition labels you've already declared in App Store Connect, then diffs them against what the scanner actually found in code. Nobody does declared-vs-actual validation. This is the feature that justifies the subscription and the launch post. Park until the five core scanners and reporters are live.
- **`privacylint connect replay-rejections`** — pulls last N rejections via ASC, surfaces ITMS codes, runs scanners scoped to those codes.
- **`privacylint connect check-sdk-versions`** — cross-references SDKs in your latest archive against `ThirdPartySDKList`. Catches the Firebase→nanopb case at submission time.
- `.xcodeproj` parsing for platform detection — currently we fall back to "assume all" with a one-line note. Foundation `PropertyListSerialization` can read pbxproj; do once the core scanners are stable.

## Notes / open items
- No git remote yet — commits are local only. Add a remote before relying on push.
- British English enforced in user-facing strings.
- Constraints: no Firebase, no CoreData, SPM-only, MIT licence.
