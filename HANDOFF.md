# PrivacyLint — HANDOFF

_Last updated: 2026-06-08 (terminal reporter shipped — first usable UX surface)_

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

## Current state — Steps 1-9 ✅ **engine complete; all 5 scanners shipped**
- `5e218c3` scaffold.
- `f19e324` `ProjectDiscovery` — walks the project and classifies files. 11 tests.
- `f82620b` CLI wired to discovery — `PrivacyLintCommand` passes populated `ScanContext` to `RuleRegistry`.
- `16cb1f3 feat: implement RequiredReasonAPIScanner via SwiftSyntax AST` — first real scanner. Walks `MemberAccessExprSyntax` and `DeclReferenceExprSyntax`, indexes triggering symbols from `PrivacyLintRules.RequiredReasonAPIs`, reports `file:line:column` with ITMS-91053 messaging and actionable remediation citing approved reason codes. swift-syntax `"600.0.0"..<"604.0.0"` (resolves to 603.0.1).
- **Platform-awareness** — `ApplePlatform` enum encodes the matrix: macOS is the sole exemption from Required-Reason API. `CheckStatus { passed, failed, skippedForPlatform, notImplemented }` makes the report honest. `PlatformDetector` uses `swift package describe --type json` (separate JSON-parsing entry point — direct shell-out from `swift test` deadlocks on the SPM build lock).
- `922f7c5 feat: implement PrivacyManifestValidator (ITMS-91053 cross-check)` — turns code-level warnings into App Review `.error`s. Cross-references `PrivacyInfo.xcprivacy` against `RequiredReasonAPIScanner.detectUsage(in:)`. 13-row scenario matrix in tests. `PrivacyManifestParser` is a thin Foundation wrapper.
- `341ac94 feat: implement DependencyResolver (ITMS-91061 / Firebase→nanopb)` — reads `Package.resolved` and `Podfile.lock`, cross-references each (transitive) dep against `ThirdPartySDKList`, checks the local checkout for `PrivacyInfo.xcprivacy`. Firebase→nanopb headline rejection caught. applicablePlatforms = ALL. SDK matcher normalises identities (strips `-ios-sdk`/`-ios-spm`/`-ios`/`-cocoa` but NOT `-swift`).
- `7346423 feat: implement TrackingDomainChecker (static URL-literal scope)` — AST walks for `StringLiteralExprSyntax`, matches against `KnownTrackerDomains` (Meta, GA, Mixpanel, Amplitude, AppsFlyer, etc.), reconciles against `NSPrivacyTracking` + `NSPrivacyTrackingDomains`. README explicit about static-only scope.
- **`8c0c407 feat: implement AIConsentDetector (Nov 2025 launch differentiator)`** — the final scanner. Two AST passes: (1) AI usage via static URL literals matching `AIServiceEndpoints.hosts` + `import OpenAI/Anthropic/…` SDK imports; (2) consent surface via identifier-component matching (`hasAcceptedAIConsent` → splits to `[has, accepted, ai, consent]` → has both AI and consent tokens) or string literals with provider name + consent verb. Severity **capped at `.warning`** by design — static analysis can't prove the UI is actually shown before the call; false positives erode trust faster than misses. camelCase splitter handles acronym→word boundaries (`AIConsent`→`AI+Consent`) — caught during test pass. False-positive guards covered: `pairSelected`, `aiAvailable`, `hasAcceptedTrackingConsent` (ATT, not AI) all silent. End-to-end smoke: AI URL with no consent → warning citing OpenAI; AI URL + `hasAcceptedAIConsent` + `presentAIDisclosure` → silent.
- **All 5 scanners ship.** `notImplemented` no longer appears in any JSON output.
- **`1e5f186 feat: implement TerminalReporter with ANSI colour and TTY detection`** — replaces the "report not yet implemented" stub with a hierarchical block-per-scanner layout: badges (✓/✗/—), severity-coloured violations with `file:line:column`, wrapped messages, grey fix-it lines, summary footer with errors/warnings counts and the "App Review will block" postscript. Paths rendered relative to `ScanResult.projectPath` via canonical `pathComponents` comparison (same `/tmp ↔ /private/tmp` defence as `ProjectDiscovery`). ANSI auto-disabled when stdout is not a TTY; `--no-color` flag for explicit override. 9 reporter tests. HTML reporter still a stub.
- `swift build` ✅, `swift test` ✅ (113 tests pass — 8 Swift Testing suites + XCTest layer).

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
The engine is complete. Five scanners, four ITMS rejection codes covered (91053, 91061, 91065-adjacent, AI-consent guidance). Remaining work is shipping, polish, and distribution — not new scanner logic.

1. **HTML reporter** — same data shape as JSON/terminal, standalone HTML page suitable for sticking in CI artifacts. Inline CSS only, no external assets.
2. **CI exit codes** — currently the CLI always exits 0. Add: errors → exit 1, warnings-only → exit 0 (configurable via `--warnings-as-errors`).
3. **`brew install privacylint`** — Homebrew formula. SPM-only, single executable, easy.
4. **`mint install`** — alternative install path.
5. **Distribution** — the four blog posts (ITMS-91053 / 91061 / tracking-domain / AI-consent). Reuse the validators' real output verbatim with file:line + fix-it lines. Include the "report a missing SDK match" link.
6. **Show HN** — terminal reporter now produces a screenshot-worthy demo. Need one real-app run (open-source iOS app) before posting.
7. **v2 — ASC integration** (`privacylint connect validate-against-asc`) — the subscription-justifying differentiator. Diffs declared privacy nutrition labels in App Store Connect against what the scanners found. Keychain entry `apple-app-store-connect`, keys at `~/.appstoreconnect/private_keys/`.

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
