Hi @Dimillian — IceCubesApp doesn't currently ship a `PrivacyInfo.xcprivacy`, and the app reads `UserDefaults` in a couple of places that fall under Apple's Required Reason API rules (in force since May 2024). App Store Connect rejects submissions for this with `ITMS-91053` ("Missing API declaration").

This PR adds the manifest with the narrowest declaration the code actually needs.

## Why these two reason codes

| Call site                                                                          | Category                                  | Reason  |
| ---------------------------------------------------------------------------------- | ----------------------------------------- | ------- |
| `Packages/Env/Sources/Env/UserPreferences.swift:88` — `UserDefaults.standard`     | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (same-app data) |
| `Packages/Env/Sources/Env/UserPreferences.swift:109` — `UserDefaults(suiteName: "group.com.thomasricouard.IceCubesApp")` shared with widget/notification extensions | `NSPrivacyAccessedAPICategoryUserDefaults` | `1C8F.1` (same-app-group data) |
| `IceCubesApp/App/Main/IceCubesApp.swift:42` — `register(defaults:)` inside `#if DEBUG` | same                                       | wouldn't ship in release; CA92.1 covers it if it ever does |

No other Required Reason API categories apply — I checked for `FileTimestamp`, `SystemBootTime`, `DiskSpace`, and `ActiveKeyboards` symbols across the codebase and didn't find real usages. No tracking domains. No AI service endpoints. So this manifest stays minimal.

## Bundling

The project uses Xcode's synchronized folder groups (`PBXFileSystemSynchronizedRootGroup` × 9 in the pbxproj), so dropping the file into `IceCubesApp/` next to `Info.plist` should add it to the main app target automatically. Please verify it lands in the *Copy Bundle Resources* phase before merging.

## Out of scope for this PR

The extension targets — `IceCubesActionExtension`, `IceCubesShareExtension`, `IceCubesNotifications`, `IceCubesAppWidgetsExtension` — all import `Env` and therefore transitively use `UserDefaults`. Each is a separate bundle and will need its own `PrivacyInfo.xcprivacy` copy to be fully compliant. Happy to follow up with a second PR for those if you'd like; I split it out so the main-app fix is reviewable on its own.

## How I found this

I ran [PrivacyLint](https://github.com/Neelagiri65/privacylint) — a Swift CLI I built to catch this category of rejection — against the repo. It flagged 1 blocking error (no manifest) and 19 Required-Reason warnings; on triage, the two `UserDefaults` ones above are real and the other 14 (`creationDate`) are SwiftData `@Model` property names rather than `URLResourceValues.creationDate` calls, so they don't need declaration. PrivacyLint v1 can't statically disambiguate those — it's a documented limitation I'm fixing in v0.2.

Happy to iterate on anything here.
