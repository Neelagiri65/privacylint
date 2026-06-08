# PrivacyLint

**Catch every App Store privacy rejection before you hit submit.** A Swift CLI
that runs in your build or CI and tells you, in plain English with file and
line numbers, what Apple's review will flag — Required Reason APIs without
declared reasons, third-party SDKs missing privacy manifests, `PrivacyInfo.xcprivacy`
mismatches, undeclared tracking domains, and AI service calls missing consent UI.

Built for indie devs and small teams who don't have a compliance person and
don't want to spend a week chasing an `ITMS-91053` rejection email.

> ⚠️ **Status: scaffold.** Architecture, models, CLI, file discovery, and rule
> tables are wired end-to-end. Scanner implementations are landing one at a
> time, test-first.

## Why this exists

You hit submit. Three days later: `ITMS-91053: Missing API declaration`. Apple
won't tell you which file. The API is buried in a transitive dependency of
Firebase. You spend a weekend grepping. You resubmit. Three days later: another
rejection, different code. This happens to roughly **400,000 submissions a
year** — the fastest-growing rejection category, with new rules stacking up
each year (manifests in 2024, AI consent in late 2025, age-rating changes in
2025, mandatory Xcode 26 SDK in 2026).

Existing tools either died after the May 2024 manifest deadline, work as
grep-only weekend scripts, sell only to enterprises at enterprise prices, or
check your App Store *listing* instead of your actual code. PrivacyLint reads
the **source** — properly, with an AST so it can tell a comment from a real
call — and stays current as Apple moves the goalposts.

## Platform-aware by design

A macOS-only project doesn't need to declare Required-Reason API usage —
Apple exempts macOS from that section. PrivacyLint reads your `Package.swift`
(`swift package describe --type json`) to detect which Apple platforms you
target, and **skips checks that don't apply**. The report says exactly which
platforms each check was run for:

```json
{
  "detectedPlatforms": ["macOS"],
  "outcomes": [
    { "ruleIdentifier": "required-reason-api",
      "status": "skippedForPlatform",
      "applicablePlatforms": ["iOS", "iPadOS", "macCatalyst", "tvOS", "visionOS", "watchOS"] },
    ...
  ]
}
```

The four `CheckStatus` values — `passed`, `failed`, `skippedForPlatform`,
`notImplemented` — exist so the report never silently drops a check. If
something didn't run, you see why. The grep tools either flag macOS false
positives or silently miss visionOS scope; PrivacyLint tells you what it did
and didn't check.

`.xcodeproj` parsing is v2; if you scan a pure Xcode project today,
detection falls back to "assume all platforms" with a one-line note.

## AI consent detection — the differentiator

Since November 2025, Apple has rejected apps that send user content to
external AI/LLM services without an explicit in-app consent surface.
The `ai-consent` scanner is the only one in the indie tool space that
checks for this. It works in two steps:

1. **Detects AI service usage** — static URL literals matching known
   provider endpoints (`api.openai.com`, `api.anthropic.com`,
   `api.mistral.ai`, `api.cohere.com`, Google AI's `*.googleapis.com`)
   and `import OpenAI` / `import Anthropic` / etc.
2. **Looks for a consent surface** — any identifier (variable, function,
   type) whose camelCase components include BOTH an AI token (`ai`,
   `openai`, `llm`, `gpt`, `claude`, `gemini`, `mistral`, `cohere`) and a
   consent token (`consent`, `accept`, `agree`, `optin`, `permission`,
   `allow`, `disclosure`). Or a string literal containing an AI provider
   name AND a consent verb.

If AI usage is found but no consent surface is detected, the scanner
emits a **warning** — never an error — pointing at the first AI call
and naming the providers. Severity is capped because static analysis
cannot prove a consent UI is shown to the user *before* the call:
false positives here would erode trust faster than a missed catch.

If no AI usage is detected, the scanner short-circuits silently — your
non-AI app isn't scrutinised for consent.

**False-positive guards** built in:
- `pairSelected` → not flagged (no AI token; "pair" ≠ AI)
- `aiAvailable` → not flagged (no consent token)
- `hasAcceptedTrackingConsent` → not flagged (this is ATT, not AI)

**Out of scope (v1)**, documented honestly:
- Runtime-constructed URLs (`base + "/openai"`, interpolated hosts).
- Localised consent strings (keyword list is English-only).
- Verifying the consent UI is actually shown before the first AI call.

## Tracking-domain detection — what we catch and what we don't

The `tracking-domain-declaration` scanner reads your Swift source and flags
calls to known tracker hosts (Meta Pixel, Google Tag Manager, Mixpanel,
Amplitude, AppsFlyer, Adjust, Branch, Segment, Sentry, AppLovin, and others)
that aren't declared in your `NSPrivacyTrackingDomains`. **v1 catches:**

- Static URL string literals: `URL(string: "https://facebook.com/tr/event")`
- Bare hostname literals: `"facebook.com"`
- Subdomain coverage by apex declarations (`connect.facebook.net` → `facebook.net`)
- Both `NSPrivacyTracking=false` contradictions and undeclared-domain errors

**v1 does NOT catch:**

- **Runtime-constructed URLs:** `base + "/track"`, `"https://\(host)/event"`,
  domains read from `Info.plist`, `.strings`, JSON config, or env vars. We
  surface only what's statically visible in the AST.
- **SDK-internal endpoints:** if your code calls `Analytics.log(...)` and the
  SDK's own endpoint is set in its config, we won't find the domain — the
  `DependencyResolver` scanner is the complement here (it flags the SDK
  itself).
- **Objective-C source.**

Static-literal detection is genuinely useful (it catches most direct integrations
of trackers via `URL(string:)`), but it is not exhaustive. Treat a green
tracking-domain check as "no static reference found" rather than "your app
makes no tracking calls." Runtime URL analysis is on the v2 roadmap.

## Known limitations

- **Objective-C source is collected but not parsed in v1.** SwiftSyntax is
  Swift-only. If your project has `.m`/`.h` files that call Required Reason
  APIs (e.g. `NSFileManager` timestamp queries), the v1 scanner will miss
  them. A meaningful chunk of older iOS projects still mix Swift and ObjC;
  treat the report as a Swift-only signal until v2 adds an ObjC sidecar.
- **No semantic type resolution.** A user-defined `creationDate` property on
  an unrelated type may be flagged the same way as `FileManager` access. False
  positives are easier to dismiss than rejections; we err on the side of
  surfacing more.
- **No macro expansion.** Macro-emitted code is treated as the call site.
- **`#if` branches are all scanned.** A Required Reason API gated behind
  `#if DEBUG` is still reported.

## What it checks

| Check | Rule ID | Status |
| --- | --- | --- |
| Required Reason API usage vs. declared reasons | `required-reason-api` | scaffold |
| Third-party SDK privacy manifests | `third-party-sdk-manifest` | scaffold |
| `PrivacyInfo.xcprivacy` validation | `privacy-manifest-validation` | scaffold |
| Tracking domain declarations | `tracking-domain-declaration` | scaffold |
| AI service consent (Nov 2025+) | `ai-consent` | scaffold |

The **AI consent** check is the differentiator — no existing tool checks for it.

## Design

- **Swift 5.9+**, [Swift Argument Parser](https://github.com/apple/swift-argument-parser) for the CLI.
- **[SwiftSyntax](https://github.com/apple/swift-syntax)** for AST-level analysis — it understands comments, test targets and dead code, unlike grep-based tools.
- **SPM-only.** No CocoaPods for the tool itself.
- **Rule tables** (`PrivacyLintRules`) are plain data, refreshed monthly as Apple changes requirements.
- Output formats: terminal (coloured), JSON, HTML.

## Usage

```bash
privacylint --path ./MyApp --format terminal
```

| Option | Default | Description |
| --- | --- | --- |
| `--path`, `-p` | `.` | Path to the Xcode project or Swift package. |
| `--format`, `-f` | `terminal` | `terminal`, `json` or `html`. |

## Building from source

```bash
swift build
swift test
swift run privacylint --path ./MyApp
```

## CI integration

PrivacyLint exits **1** when at least one `.error` violation is found (the
rejection-class ones — `ITMS-91053`, `ITMS-91061`), and **0** otherwise.
Drops straight into GitHub Actions / Xcode build phases / pre-commit hooks
with no extra plumbing.

### GitHub Actions

```yaml
- name: PrivacyLint
  run: swift run privacylint --path . --format terminal
```

The job fails on errors and passes on warnings. Use `--warnings-as-errors`
for strict mode where any finding fails the build:

```yaml
- name: PrivacyLint (strict)
  run: swift run privacylint --path . --warnings-as-errors
```

### Xcode build phase

Add a Run Script phase:

```bash
swift run --package-path "$PROJECT_DIR/.privacylint" privacylint --path "$PROJECT_DIR"
```

PrivacyLint emits Xcode-compatible `file:line:column` references, so each
violation becomes a clickable warning/error in the Issue navigator.

### Pre-commit hook

```yaml
- repo: local
  hooks:
    - id: privacylint
      name: PrivacyLint
      entry: swift run privacylint --path .
      language: system
      pass_filenames: false
```

ANSI colour is auto-disabled when stdout is not a TTY (your CI log won't
fill with escape codes). Pass `--no-color` to force-disable.

## Installation (planned)

```bash
brew install privacylint
mint install <org>/privacylint
```

## Architecture

```
Sources/
  PrivacyLint/        CLI entry point (argument parsing → engine → reporter)
  PrivacyLintCore/    Analysis engine (protocol-based, testable)
    Scanner/          ComplianceScanner protocol + one scanner per check
    Models/           Violation, ScanResult, PrivacyManifest
    Rules/            RuleRegistry — the catalogue of checks
    Reports/          Terminal / JSON / HTML reporters
  PrivacyLintRules/   Apple's current rule data (update monthly)
```

Each scanner conforms to `ComplianceScanner` so it can be tested in isolation.

## Licence

MIT — see [LICENSE](LICENSE).
