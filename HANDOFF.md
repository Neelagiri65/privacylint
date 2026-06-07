# PrivacyLint — HANDOFF

_Last updated: 2026-06-08_

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

## Current state — Step 1 (scaffold) COMPLETE ✅
Committed: `5e218c3 chore: scaffold PrivacyLint CLI project structure` (27 files).
- `swift build` ✅ (Swift 6.3.2), `swift test` ✅ (11/11 pass), `swift run privacylint --path . --format terminal` ✅.
- Architecture only — **no scanning logic implemented**. Every scanner throws `ScannerError.notImplemented`; `RuleRegistry.run` skips those, so the pipeline runs end-to-end with empty output.

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
1. **User reviews the architecture** before engine work begins (explicitly requested).
2. Then, before any AST code: run `/research-first` on the SwiftSyntax API (per session rules).
3. Build scanners in order, each test-first: RequiredReasonAPIScanner (SwiftSyntax visitor → detect triggering symbols, ignore comments/test targets) → DependencyResolver (parse Package.swift/Podfile → cross-ref ThirdPartySDKList) → PrivacyManifestValidator (parse `.xcprivacy` plist → reconcile reasons vs usage) → TrackingDomainChecker → AIConsentDetector.
4. Add the file-discovery logic that populates `ScanContext` (currently empty).

## Notes / open items
- No git remote yet — commits are local only. Add a remote before relying on push.
- British English enforced in user-facing strings.
- Constraints: no Firebase, no CoreData, SPM-only, MIT licence.
