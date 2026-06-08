# PrivacyLint — HANDOFF

_Last updated: 2026-06-08 (LAUNCHED + IceCubesApp PR drafted locally; PR push & open are the next session's first action)_

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
- `1e5f186 feat: implement TerminalReporter with ANSI colour and TTY detection` — hierarchical block-per-scanner layout; ANSI auto-disabled on non-TTY; `--no-color` flag; canonical `pathComponents` path-stripping with `/tmp ↔ /private/tmp` defence.
- **`3c84cdb feat: CI exit codes — exit 1 on errors, --warnings-as-errors strict mode`** — unblocks the CI adoption path. Contract: errors → exit 1, warnings-only → exit 0 (non-strict CI keeps passing), `--warnings-as-errors` escalates warnings to failures. Decision logic is `ScanResult.exitCode(warningsAsErrors:)` — pure, unit-tested, the spec announced as the public contract for CI consumers. README adds copy-pasteable snippets for GitHub Actions, Xcode build phases, and pre-commit.
- HTML reporter still a stub — parked per revised priority (post-launch nice-to-have).
- **`8a648a2 release: v0.1.0 — first launchable version`** — CLI version bumped 0.0.1 → 0.1.0, tag `v0.1.0` created locally. Homebrew formula drafted at `dist/homebrew/privacylint.rb` with a non-trivial test block that creates a Required-Reason fixture, asserts scanner detection AND `ITMS-91053` in output AND non-zero exit. `dist/homebrew/README-tap.md` is the README the `homebrew-privacylint` tap repo will use. **`RELEASE.md`** is the full runbook: pre-flight gh commands to create both repos, tarball SHA hashing, tap-repo formula bump, smoke-install verification.
- **`aae0157 docs: draft ITMS-91053 blog post for nativerse-ventures.com`** — `dist/blog/itms-91053-missing-api-declaration.md`. ~1,300 words. Structured as the answer to a panic Google search: opens with the verbatim Apple rejection email, gives the complete manual fix (XML + reason-code table), then the three traps that defeat the manual fix (transitive deps / SDK manifests / wrong content), only THEN reveals PrivacyLint with verbatim CLI output from `/tmp/pl-itms-91053` and `/tmp/pl-firebase`. brew install one-liner + GitHub Actions snippet + the "report a missing SDK match" issue link. British English; senior-dev-to-peer tone; SEO keywords audited (`ITMS-91053` x10, `PrivacyInfo.xcprivacy` x8, `NSPrivacy*` x18, all natural). Ready to drop into the publishing pipeline alongside the tap publication.
- **LAUNCHED (this turn).** Public repos created, code pushed, v0.1.0 release cut, Homebrew tap published, brew install verified producing a working binary.
  - https://github.com/Neelagiri65/privacylint (main repo, master pushed, v0.1.0 tag pushed, GitHub release at /releases/tag/v0.1.0)
  - https://github.com/Neelagiri65/homebrew-privacylint (tap repo, Formula/privacylint.rb with sha256 `2d092c02aa0bb0c223c9463838535dda81c52b0f86528be78eae031f4598b2cd`)
  - `/opt/homebrew/bin/privacylint` — 0.1.0, exits 1 on errors as designed.
- **Real-app finding on IceCubesApp** (Mastodon iOS, SwiftUI, popular open-source) — 1 ITMS-91053 blocking error (no PrivacyInfo.xcprivacy in the repo) + 19 Required-Reason warnings across 12 files. Captured to `dist/launch/icecubes-scan.txt`. Honest caveat: some `creationDate` warnings are SwiftData @Attribute false positives — documented in the Reddit post and the v2 roadmap.
- **`b805684 docs(launch): real-app finding…`** — Reddit (r/iOSProgramming) and Swift Forums post drafts saved to `dist/launch/`. Blog post saved to `dist/blog/itms-91053-missing-api-declaration.md`.
- **IceCubesApp PR — drafted locally, NOT pushed/opened**. The fork exists publicly (`https://github.com/Neelagiri65/IceCubesApp`), the local commit `6a87a8d5` is on branch `add-privacy-manifest` at `/tmp/pl-pr/IceCubesApp` with the correct `PrivacyInfo.xcprivacy`. Triage was deliberate: only 2 of 19 PrivacyLint warnings were real (both `UserDefaults` in `UserPreferences.swift`); the 14 `creationDate` findings are confirmed SwiftData `@Model` property names — false positives documented in the PR body. PR body, manifest XML, exact resume commands all in `dist/launch/icecubes-pr-draft.md` and `dist/launch/icecubes-pr-body.md`.
- **What Claude did NOT do**: publish the blog post to nativerse-ventures.com (no API access to your site); post on Reddit / Swift Forums (deliberately user-side — accounts, voice, response handling); push the IceCubesApp branch or open the PR (user signalled handoff before that visible action).

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

## How to resume — first 60 seconds of next session

1. `cd /Users/srinathprasannancs/devtools/privacylint && git log --oneline -5` — confirm last commit is the HANDOFF update committed at end of this session.
2. `git status` — should be clean. Tree is in a publishable, stable state.
3. Read this HANDOFF top-to-bottom. Specifically the **NEXT** list and the **IceCubesApp PR — drafted locally** bullet under Current state. The PR is the FIRST action; everything else flows from it.
4. If `/tmp/pl-pr/IceCubesApp` still exists: `cd` there and follow the resume block in `dist/launch/icecubes-pr-draft.md`. If gone: re-clone the fork.
5. `swift test` to confirm 119 tests still pass and nothing has rotted.

## NEXT
**One push and one blog post from launchable.** The user runs the gh commands in `RELEASE.md` when ready — Claude has not pushed anything to GitHub. See `RELEASE.md` for verbatim commands.

1. ~~Publish the tap~~ ✅ done.
2. **Finalise + push the IceCubesApp PR** — local commit `6a87a8d5` on branch `add-privacy-manifest` in `/tmp/pl-pr/IceCubesApp`. The PR body lives at `dist/launch/icecubes-pr-body.md`; exact resume commands in `dist/launch/icecubes-pr-draft.md`. Review the manifest XML + PR body, then run the `git push` + `gh pr create` block from the draft doc. **Note**: `/tmp/pl-pr/IceCubesApp` is on /tmp — survives a reboot but not a /tmp clean. If gone, the fork at `Neelagiri65/IceCubesApp` is still there; reclone + recommit (PrivacyInfo.xcprivacy and commit message are reproducible from `dist/launch/icecubes-pr-draft.md`).
3. **Publish the blog post** — drop `dist/blog/itms-91053-missing-api-declaration.md` into nativerse-ventures.com. Update `dist/launch/reddit-r-iOSProgramming.md`'s `[link once published]` placeholder. Update the same draft's IceCubes section to link the now-open PR URL.
4. **Post Reddit + Swift Forums** — drafts in `dist/launch/`. r/iOSProgramming, r/IndieDevs / Indie Dev Monday, swift.org/forums. Lead with the IceCubesApp finding for credibility.
5. **Show HN** — once the blog post has 24-48h on Reddit and the IceCubes PR has any movement.
6. **v0.2.0 milestone** (per launch-advice feedback): "Reduced false positives on SwiftData `@Model` property declarations." The IceCubesApp false-positive cluster (14/19 warnings) is the motivator. Approach: extend `RequiredReasonAPIScanner` to recognise `@Model` / `@Attribute` annotation context and skip property declarations within those types. Tangible improvement to announce to the same audience.
7. **Week-1 metrics to watch**: GitHub stars + "missing SDK match" issues filed. Everything else is noise.
4. **HTML reporter** — post-launch nice-to-have. Same data shape; standalone HTML; inline CSS; for CI artifact uploads.
5. **`mint install`** — alternative install path; minor.
6. **v2 — ASC integration** (`privacylint connect validate-against-asc`) — the subscription-justifying differentiator. Keychain entry `apple-app-store-connect`, keys at `~/.appstoreconnect/private_keys/`.

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
