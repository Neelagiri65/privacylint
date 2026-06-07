# PrivacyLint

**ESLint for Apple's App Store privacy requirements.** A Swift CLI that scans
your iOS/macOS Xcode project and reports what would block your next submission —
before you hit submit.

> ⚠️ **Status: scaffold.** The architecture, models, CLI and rule tables are in
> place; the scanning engine is being built step by step. Scanners currently
> return "not yet implemented".

## Why

In 2024 Apple reviewed 7.77 million submissions and rejected roughly 400,000 for
privacy violations — the fastest-growing rejection category. The rules keep
changing: Required Reason APIs, third-party SDK privacy manifests, tracking
domain declarations, and — since November 2025 — AI service consent. PrivacyLint
stays current so you don't get rejected for a rule that shipped last month.

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
