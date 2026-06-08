# Research — Platform-aware scanning

_Date: 2026-06-08. Status: ready for review. No code written yet._

## Step 1 — What I'm about to build
I am about to add **platform-awareness** to PrivacyLint so that each scanner knows the set of Apple platforms the project targets (iOS, iPadOS, tvOS, visionOS, watchOS, macOS, macCatalyst), runs only when at least one applicable platform is present, and the final report shows **per-platform compliance status** — so a universal SwiftUI project targeting iOS + macOS + visionOS gets one scan and one breakdown.

## Step 2 — Existing solutions
- **Oxbit Preflight** (Mar 2026) — App Store listing markets it as a Mac app for scanning Xcode projects. No mention of multi-platform target awareness; appears to scan source uniformly regardless of platforms. Our differentiator: a universal-app project ships to ≥3 platforms and Oxbit doesn't tell you which platform a finding actually blocks.
- **Free CLIs (stelabouras, Wooder, techinpark, crasowas)** — all platform-agnostic; they treat every project as "iOS." Same false-positive class on macOS-only projects (flagging `UserDefaults.standard` as a required-reason violation when macOS doesn't require declaration).
- **Privado.ai** — enterprise; no public-facing per-platform reporting that I can find.
- **App Privacy Manifest Fixer** — generates the manifest; not a scanner; not platform-aware.

**Why nobody has it.** Reading deployment targets is genuinely fiddly for `.xcodeproj` projects (pbxproj is a NeXTSTEP-style plist, not XML), and the platform/requirement matrix isn't on a single Apple page — you have to assemble it from the manifest docs and TN3183. The grep tools never had a stable place to put this logic.

## Step 3 — Architectural constraints
| Constraint                                                         | Approach satisfies?                                                                  |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| SPM-only, macOS 13+                                                | ✅ Detection uses `swift package` CLI which ships with the toolchain                  |
| No xcodebuild requirement at runtime for SPM-only projects         | ✅ `swift package describe --type json` is enough; xcodebuild only needed for `.xcodeproj` |
| British English in user-facing strings                             | ✅ — platform names rendered as "iOS", "macOS" etc. (Apple's own spelling)            |
| ScanContext is `Sendable` and immutable                            | ✅ Adding `platforms: Set<ApplePlatform>` is a `Sendable` value                       |
| Don't break the existing 20 passing tests                          | ✅ Default platforms is "unknown → run all checks" to preserve current behaviour      |
| The added complexity must be testable in isolation                 | ✅ Detection separated into a `PlatformDetector` enum; pure-data helpers, mockable    |
| Architectural test before any code (ContextKey lesson)             | ✅ See **Step 5**                                                                     |

## Step 4 — The platform/requirement matrix (the actual research result)

Consensus across multiple secondary sources (Apple's primary docs are JS-rendered and not fetchable via WebFetch — citations below; I'd verify against Apple's live page before shipping):

| Apple platform     | `PrivacyInfo.xcprivacy` required?  | Required-Reason APIs (`NSPrivacyAccessedAPITypes`) required? | Tracking (`NSPrivacyTracking`, `NSPrivacyTrackingDomains`) | Collected data (`NSPrivacyCollectedDataTypes`) |
| ------------------ | ---------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------- | ---------------------------------------------- |
| iOS                | ✅                                  | ✅                                                            | ✅                                                          | ✅                                              |
| iPadOS             | ✅ (same as iOS)                    | ✅                                                            | ✅                                                          | ✅                                              |
| tvOS               | ✅                                  | ✅                                                            | ✅                                                          | ✅                                              |
| visionOS           | ✅                                  | ✅                                                            | ✅                                                          | ✅                                              |
| watchOS            | ✅                                  | ✅                                                            | ✅                                                          | ✅                                              |
| **macOS**          | ✅                                  | **❌ — exempt**                                                | ✅                                                          | ✅                                              |
| Mac Catalyst       | ✅                                  | ✅ (treated as iOS for this purpose)                          | ✅                                                          | ✅                                              |

Implication for the scanner pipeline:
- `RequiredReasonAPIScanner` → run iff `platforms.contains(where: { $0.requiresRequiredReasonAPI })`. macOS-only projects: scanner returns `.skipped`, not `.passed` with violations.
- `DependencyResolver` (SDK privacy-manifest list) → run on all platforms. Third-party SDK manifests required everywhere.
- `PrivacyManifestValidator` → run on all platforms; only enforces the Required-Reason section when an iOS-family platform is present.
- `TrackingDomainChecker` → run on all platforms.
- `AIConsentDetector` → run on all platforms (AI consent isn't a manifest rule; it's a behaviour rule, and applies anywhere the app does AI calls).

### How to detect platforms

**SPM project (has `Package.swift`):** `swift package describe --type json` (verified locally — see Sources). Output includes:
```json
"platforms" : [
  { "name" : "macos",    "version" : "13.0" },
  { "name" : "ios",      "version" : "17.0" },
  { "name" : "visionos", "version" : "1.0"  }
]
```
Platform name strings (lowercase): `ios`, `macos`, `tvos`, `watchos`, `visionos`, `maccatalyst`, `driverkit`. We map to our enum.

**Important nuance:** SPM's `platforms` array specifies *minimum deployment target* per platform the package supports. **Absence is not exclusion** — if `platforms` is missing or doesn't list iOS, SwiftPM still allows the package to be consumed on iOS at the SPM default. But for an *app* shipping to the App Store, the developer always declares their targets. For a *library package*, we should treat unlisted platforms as "supported, no override" — i.e. assume all platforms are in scope unless explicitly restricted via target build settings. v1 heuristic: trust the `platforms` array if non-empty; if empty, fall back to "assume all platforms" (run every check).

**Xcode project (`.xcodeproj`):** Two options.
1. **Run `xcodebuild -showBuildSettings -json -project Foo.xcodeproj`** — gives `SUPPORTED_PLATFORMS`, `IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, `TVOS_DEPLOYMENT_TARGET`, `WATCHOS_DEPLOYMENT_TARGET`, `XROS_DEPLOYMENT_TARGET`. **Cost:** xcodebuild can take 5-30s to spin up; requires full Xcode (not just Command Line Tools); won't run in non-Mac CI. For v1 acceptable — PrivacyLint already only runs on macOS.
2. **Parse `project.pbxproj` directly.** It's a NeXTSTEP plist. `PropertyListSerialization` reads it (Foundation, free). We grep `XCBuildConfiguration` → `buildSettings` → look for `*_DEPLOYMENT_TARGET` keys and `SDKROOT`. Faster, no shell-out, no Xcode dependency. Tuist's `XcodeProj` library does this; we don't need the whole library — Foundation's plist reader gets the dict tree.

**Recommendation for v1:** support SPM via `swift package describe`; defer `.xcodeproj` parsing to v2 (most indie projects are SPM-first, and the SDK list-of-tools the report already mentioned addresses pbxproj users separately when we wire DependencyResolver). Log a clear "Detected `.xcodeproj` — platform detection skipped (v1 limitation); assuming all platforms apply" when only an .xcodeproj is present.

**Fallback (no manifests at all):** assume `Set(ApplePlatform.allCases)` so every check runs. Conservative — false positives easier to dismiss than rejections.

## Step 5 — Pitfalls (web + vault failures)

1. **`platforms: []` doesn't mean "no platforms".** It means "use SPM defaults." Treat empty as "all" — guarding the wrong way silently turns off every check for libraries.
2. **Mac Catalyst is iOS for privacy purposes.** A macOS-only project that adds Mac Catalyst suddenly requires the Required-Reason section. Treat Catalyst as iOS-family.
3. **visionOS deployment-target key is `XROS_DEPLOYMENT_TARGET`** (legacy Apple internal name), not `VISIONOS_DEPLOYMENT_TARGET`. Documented gotcha when we add xcodeproj support.
4. **`swift package describe` requires a valid Package.swift.** A broken manifest crashes the CLI — wrap the shell-out and degrade gracefully.
5. **`Process` shell-out from Swift.** Standard Foundation `Process` works on macOS; pipe both stdout/stderr; bound execution time (5s).
6. **Apple's primary docs are JS-rendered.** We could not extract Apple's exact wording via WebFetch. Before shipping platform copy in user-facing strings, manually verify against `developer.apple.com/documentation/bundleresources/privacy-manifest-files` and TN3183. The matrix above is the consultant's research + multi-source consensus; it matches every secondary source I read, but cite Apple directly in any error message.
7. **`competitive-research-strawmen.md`** (vault failure) — don't assume an existing tool is bad just because it's quiet on a feature. Before claiming "Oxbit doesn't do multi-platform," I should keep checking their release notes monthly. For now, their *App Store description* doesn't claim it.

## Step 6 — How I'll know it works

**Architectural test** (must pass before any other platform-aware code lands):

```swift
@Test func macOSOnlyProjectSkipsRequiredReasonAPIScanner() throws {
    let context = ScanContext(
        projectPath: URL(fileURLWithPath: "/tmp"),
        sourceFiles: [/* file containing UserDefaults.standard */],
        platforms: [.macOS]
    )
    let result = RuleRegistry().run(context)
    let rra = result.outcomes.first { $0.ruleIdentifier == "required-reason-api" }
    #expect(rra?.status == .skippedForPlatform)
    #expect(rra?.violations.isEmpty == true)
}

@Test func multiPlatformProjectStillRunsRequiredReasonAPIScanner() throws {
    let context = ScanContext(projectPath: ..., platforms: [.iOS, .macOS])
    // iOS is in the set → scanner runs → violations flagged
}

@Test func emptyPlatformsAssumeAllAndRunEverything() throws {
    let context = ScanContext(projectPath: ..., platforms: [])
    // Library or unknown — assume all → run everything
}

@Test func swiftPackageDescribeProducesPlatformsArray() throws {
    let detector = PlatformDetector()
    let platforms = try detector.detect(at: URL(fileURLWithPath: "/path/to/spm/project"))
    #expect(platforms.contains(.macOS))
}

@Test func tnTrackingDomainScannerRunsEvenOnMacOSOnly() {
    // Once TrackingDomainChecker is implemented — sanity for the inverse rule.
}
```

And a per-platform reporter assertion: the JSON output gains a `platforms: ["iOS", "macOS", "visionOS"]` field and each `CheckOutcome` carries `applicablePlatforms` and a `status` enum (`passed`, `failed`, `skippedForPlatform`, `notImplemented`).

## Recommendations

### 1. New types
```swift
public enum ApplePlatform: String, Sendable, Codable, CaseIterable, Hashable {
    case iOS, iPadOS, tvOS, watchOS, visionOS, macOS, macCatalyst

    public var requiresRequiredReasonAPI: Bool {
        switch self {
        case .iOS, .iPadOS, .tvOS, .watchOS, .visionOS, .macCatalyst: return true
        case .macOS: return false
        }
    }
    /// Privacy manifest itself is required on every distributed platform.
    public var requiresPrivacyManifest: Bool { true }

    /// Map the lowercase name SPM emits to our enum. Unknown → nil.
    public static func fromSPMName(_ raw: String) -> ApplePlatform? { /* ios→.iOS, etc. */ }
}
```

iPadOS is here for completeness even though SPM rolls it into `iOS` — keeps reports honest when we later parse xcodeproj or `INFOPLIST_KEY_LSApplicationCategoryType` and discover an iPad-specific target.

### 2. ScanContext additions
```swift
public struct ScanContext: Sendable {
    // ... existing fields
    public let platforms: Set<ApplePlatform>      // empty = "unknown, assume all"

    public init(..., platforms: Set<ApplePlatform> = []) { ... }
}
```

### 3. ComplianceScanner extension
```swift
public protocol ComplianceScanner: Sendable {
    var applicablePlatforms: Set<ApplePlatform> { get }   // default: all
    // existing fields
}

public extension ComplianceScanner {
    var applicablePlatforms: Set<ApplePlatform> { Set(ApplePlatform.allCases) }
}

// RequiredReasonAPIScanner overrides:
public var applicablePlatforms: Set<ApplePlatform> {
    Set(ApplePlatform.allCases.filter { $0.requiresRequiredReasonAPI })
}
```

`RuleRegistry.run` checks the intersection: `context.platforms.isEmpty || !applicable.isDisjoint(with: context.platforms)` → run; else emit `CheckOutcome(status: .skippedForPlatform)`.

### 4. CheckOutcome status
Currently `CheckOutcome` is `(passed: Bool, violations: [Violation])`. Introduce:
```swift
public enum CheckStatus: String, Sendable, Codable {
    case passed              // ran, no errors
    case failed              // ran, blocking errors
    case skippedForPlatform  // not applicable to this project's platforms
    case notImplemented      // (replaces the silent skip in the registry)
}
```
This makes the JSON output non-lying: today a not-implemented scanner is invisible. After: it's a `skipped` entry. The terminal reporter renders skipped as "—" so the user can audit completeness.

### 5. PlatformDetector
```swift
public enum PlatformDetector {
    public static func detect(at projectPath: URL) throws -> Set<ApplePlatform> {
        if FileManager.default.fileExists(atPath: projectPath.appendingPathComponent("Package.swift").path) {
            return try detectFromSPM(at: projectPath)
        }
        // v1: log a warning, return empty (= assume all).
        return []
    }
    
    private static func detectFromSPM(at projectPath: URL) throws -> Set<ApplePlatform> {
        // Shell out to `swift package describe --type json` with cwd = projectPath
        // Parse JSON, map each platform.name to ApplePlatform via fromSPMName
        // Bounded timeout (5s); on failure return []
    }
}
```

Wire `PlatformDetector.detect` into `PrivacyLintCommand.run` between `ProjectDiscovery.discover` and `RuleRegistry().run`. Detection failure is non-fatal; emit a warning and proceed with empty (= all).

### 6. Reporter changes
- `ScanResult` gains `detectedPlatforms: [ApplePlatform]`.
- Each `CheckOutcome` gains `applicablePlatforms: [ApplePlatform]` and `status: CheckStatus`.
- JSON: existing fields preserved; new fields additive (backwards-compatible for any consumer parsing the v0 shape).
- Terminal (when we implement it): one line per check with status emoji + per-platform legend at the bottom for multi-platform projects.

### 7. Out of scope for this phase
- `.xcodeproj` parsing (deferred to v2 — log "skipped, assuming all platforms").
- Per-target platform detection in a multi-target Xcode project (would require `xcodebuild -list` + per-target build settings).
- Per-platform deployment-target version checks (e.g. "this API was added in iOS 17"). Different problem space.

## Step 7 — Confirm and proceed
Awaiting sign-off on:
1. **`ApplePlatform` enum** with the matrix in §1 (macOS exempt from Required-Reason only).
2. **`CheckStatus` enum** replacing the silent skip — opt for honesty: not-implemented and skipped-for-platform are visible in the report.
3. **`PlatformDetector` via `swift package describe`** for v1; `.xcodeproj` deferred with a clear warning.
4. **Empty platforms = assume all** (conservative, keeps existing tests passing and avoids silent under-scanning on libraries).
5. **Per-check `applicablePlatforms` + per-result `detectedPlatforms`** in the JSON.
6. **Architectural tests** (§5) before any production code.

If yes, the order of work is: types (`ApplePlatform`, `CheckStatus`, `applicablePlatforms`) → tests → `PlatformDetector` → wire into CLI → update existing scanner + tests to declare `applicablePlatforms` → run end-to-end against a macOS-only synthetic project and confirm the scanner is correctly skipped.

---
## Sources
- [Apple — Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) (JS-rendered; verify wording manually before shipping)
- [Apple — Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple — TN3183: Adding required reason API entries to your privacy manifest](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [Apple — Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
- [Apple — `PackageDescription.SupportedPlatform`](https://developer.apple.com/documentation/packagedescription/supportedplatform)
- [SE-0236 — Package Manager Platform Deployment Settings](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0236-package-manager-platform-deployment-settings.md)
- [Capgo — Privacy manifest for iOS apps](https://capgo.app/blog/privacy-manifest-for-ios-apps/) — corroborates the iOS-family scope
- [Xojo blog — Apple's new privacy manifest requirements](https://blog.xojo.com/2024/03/20/apples-new-privacy-manifest-requirements/) — explicit "iOS, iPadOS, tvOS and visionOS" list, macOS not mentioned
- Locally verified: `swift package describe --type json` against this repo emits `platforms: [{name: "macos", version: "13.0"}]` — confirming the detection path
- Consultant's research (this turn) citing Unity and Medium pieces (corroborates macOS exempt from Required-Reason but still needs manifest)
