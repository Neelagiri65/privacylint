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
