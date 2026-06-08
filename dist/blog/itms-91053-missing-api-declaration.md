---
title: "ITMS-91053: How to Fix 'Missing API Declaration' in Your iOS App"
description: "A practical guide to the ITMS-91053 rejection — what Apple's privacy manifest requires, how to write a correct PrivacyInfo.xcprivacy by hand, and why most projects still get rejected after the obvious fix."
date: 2026-06-08
author: Neelagiri
tags: [ios, app-store-rejection, privacy-manifest, ITMS-91053, swift]
canonical: https://nativerse-ventures.com/blog/itms-91053-missing-api-declaration
---

You hit submit on Thursday. By Sunday morning, this is sitting in your inbox:

> **ITMS-91053: Missing API declaration**
>
> Your app's code references one or more APIs that require reasons, including the following API categories: `NSPrivacyAccessedAPICategoryUserDefaults`. Starting May 1, 2024, when you submit a new app or app update, you must include a `NSPrivacyAccessedAPITypes` array in your app's privacy manifest that declares the reasons your app uses these APIs. Refer to "Describing use of required reason API" for the list of allowed reasons.

You've never seen this code before. The app worked fine through every TestFlight build. Three days of waiting, gone. This guide is how you fix it — properly, not just for the line item Apple cited.

## What Apple is actually asking for

Since May 2024, certain Foundation and system APIs are classified as **Required Reason APIs**. Apple's reasoning is that these APIs can be used to fingerprint users (e.g. timestamps as a unique-ish device signal), so every call site has to declare *why* you're calling it. The full list is in Apple's [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) page. The categories that catch most apps:

- `NSPrivacyAccessedAPICategoryUserDefaults` — anything touching `UserDefaults` (yes, even reading a theme preference).
- `NSPrivacyAccessedAPICategoryFileTimestamp` — `creationDate`, `modificationDate`, `contentModificationDateKey`.
- `NSPrivacyAccessedAPICategorySystemBootTime` — `ProcessInfo.processInfo.systemUptime`, `mach_absolute_time`.
- `NSPrivacyAccessedAPICategoryDiskSpace` — `volumeAvailableCapacityKey`, `systemFreeSize`.
- `NSPrivacyAccessedAPICategoryActiveKeyboards` — `UITextInputMode.activeInputModes`.

The compliance artefact is a property-list file named `PrivacyInfo.xcprivacy`, bundled with your app, listing every category you use and an approved reason code for each.

## The manual fix

For the canonical case — your app reads a `UserDefaults` value somewhere — here is what App Review wants to see.

Create a file named `PrivacyInfo.xcprivacy` at the root of your main app target. Right-click your project, *New File…* → *App Privacy* (Xcode 15+ has a template). Or paste this XML directly:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

The reason code matters. Apple publishes a closed list of acceptable codes per category. For `UserDefaults`:

| Reason   | When to use it                                                                                        |
| -------- | ----------------------------------------------------------------------------------------------------- |
| `CA92.1` | Access information from the same app — the most common case for indie apps.                          |
| `1C8F.1` | Access information from the same app group.                                                          |
| `C56D.1` | Access information that can be accessed by other apps belonging to the same developer.               |
| `AC6B.1` | CloudKit container management — only if you're actually using CloudKit.                              |

Pick the one that matches your actual call site. If the reason code doesn't match the usage, Apple's reviewers will reject again — even though your manifest "exists." Verify your file is part of the *Copy Bundle Resources* build phase, archive, and resubmit. For 80% of single-target apps that hit only `NSPrivacyAccessedAPICategoryUserDefaults`, that's the fix.

## Why the manual fix usually isn't enough

Three traps catch developers who think the rejection is now behind them.

**Trap 1: the API was in a transitive dependency.** Apple's email cites one category. You add it. You resubmit. You get a new rejection citing a *different* category you've never heard of — `NSPrivacyAccessedAPICategoryFileTimestamp`, say. You grep your code; the symbol doesn't exist. Then you remember Firebase. Firebase pulls in `nanopb`. `nanopb` reads `file.modificationDate`. The Required Reason rule applies to every line of code shipping in your binary — yours and your dependencies' alike.

**Trap 2: third-party SDKs missing their *own* manifest.** Separate from your app's manifest, Apple maintains [a list of "commonly used SDKs"](https://developer.apple.com/support/third-party-SDK-requirements/) that must each ship a signed `PrivacyInfo.xcprivacy` of their own. If your `Package.resolved` lists one of these and the resolved version doesn't bundle a manifest, you get a *different* rejection code — `ITMS-91061` — that doesn't even tell you which SDK is missing one. You diff your `Package.resolved` against Apple's list by hand. On a Sunday. Without coffee.

**Trap 3: the manifest exists but is wrong.** Empty `NSPrivacyAccessedAPITypeReasons` arrays. Reason codes copy-pasted from a Stack Overflow answer that match a different category. Categories you declared but no longer use (dead declarations). Apple rejects all three.

These three are why projects that "fixed" ITMS-91053 in May 2024 are still getting rejected in 2026. The space is genuinely tedious to audit by hand each release.

## Or you can catch all of this before submission

I built [PrivacyLint](https://github.com/Neelagiri65/privacylint) because I got tired of auditing this by hand for every release. It's a Swift CLI that scans your project's source and dependencies, reconciles them against the current Apple rules, and tells you exactly what would be rejected — with file and line numbers. It's MIT-licensed and runs locally; nothing leaves your machine.

Run it on a project that's about to trip ITMS-91053:

```
$ privacylint --path . --format terminal
PrivacyLint v0.1.0  ·  /Users/you/MyApp
Platforms: iOS

[required-reason-api] Required Reason API usage
✓ passed · 1 warning

  warning  Sources/App/Settings.swift:5:16
           Use of `UserDefaults` triggers Apple's
           `NSPrivacyAccessedAPICategoryUserDefaults` requirement.
           fix-it: Declare one of [CA92.1, 1C8F.1, C56D.1, AC6B.1] for
           NSPrivacyAccessedAPICategoryUserDefaults in your
           PrivacyInfo.xcprivacy, or remove the call. Apple cites this in
           ITMS-91053 rejections.

[privacy-manifest-validation] Privacy manifest validation
✗ failed · 1 error

    error  Sources/App/Settings.swift:5:16
           Your project uses Required Reason APIs
           (NSPrivacyAccessedAPICategoryUserDefaults) but contains no
           PrivacyInfo.xcprivacy. App Review will reject this with ITMS-91053.
           fix-it: Add a PrivacyInfo.xcprivacy file to your main bundle and
           declare an NSPrivacyAccessedAPITypes entry for each category listed
           above.

Summary
  ✗ 1 failed   ✓ 4 passed   ·   errors: 1   warnings: 2
  Status: FAILED — App Review will block the next submission until the errors are fixed.
```

The same scanner also catches Trap 1 (transitive dependencies) and Trap 2 (third-party SDKs missing their own manifest):

```
[third-party-sdk-manifest] Third-party SDK privacy manifests
✗ failed · 1 error

    error  .build/checkouts/nanopb:1:1
           `nanopb (SwiftPM)` matches Apple's `nanopb` and is required to
           ship a privacy manifest, but no PrivacyInfo.xcprivacy was found
           in its checkout. App Review rejects this with ITMS-91061.
           fix-it: Upgrade `nanopb` to a version that ships a privacy
           manifest, or contact the SDK author. Apple's list of required
           SDKs is at https://developer.apple.com/support/third-party-SDK-requirements/
```

That's the rejection you would have got two weeks from now. With one CLI run.

### Install

```bash
brew tap Neelagiri65/privacylint
brew install privacylint
```

### CI

The CLI exits 1 on errors, 0 otherwise, so it slots into GitHub Actions with no wrapping:

```yaml
- name: PrivacyLint
  run: privacylint --path . --format terminal
```

For Xcode build phases, paste:

```bash
privacylint --path "$PROJECT_DIR"
```

The output uses Xcode-compatible `file:line:column` references, so each finding becomes a clickable warning in the Issue navigator.

## A note on the SDK list

PrivacyLint's SDK matcher works by normalising dependency identities — stripping `-ios-sdk` / `-ios-spm` / `-ios` suffixes — and looking them up in Apple's published list. New naming conventions can slip past. If you hit a rejection on an SDK that PrivacyLint didn't catch, [open an issue](https://github.com/Neelagiri65/privacylint/issues/new?title=Missing+SDK+match%3A+%3CSDK+name%3E) with the SDK name and your `Package.resolved` line. Crowdsourced fixes are how the rule data stays accurate; every reported gap helps the next developer avoid the same rejection.

## What this is

PrivacyLint is a Swift CLI for catching App Store privacy rejections — `ITMS-91053`, `ITMS-91061`, undeclared tracking domains, and missing AI-consent surfaces (Apple's November 2025 rule that no other scanner currently checks) — before you submit. MIT-licensed, SPM-only, single binary, ~120 tests behind it. Source and issues: <https://github.com/Neelagiri65/privacylint>.

If your next release is going to surface any of this anyway, you may as well find out before App Review does.
