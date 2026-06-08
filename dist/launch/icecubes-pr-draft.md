# IceCubesApp PR — DRAFT (NOT YET PUSHED OR OPENED)

## Status at handoff

| Step                                                       | Done? |
| ---------------------------------------------------------- | ----- |
| Fork `Dimillian/IceCubesApp` → `Neelagiri65/IceCubesApp`   | ✅     |
| Clone fork to `/tmp/pl-pr/IceCubesApp` with upstream remote | ✅    |
| Create branch `add-privacy-manifest`                       | ✅     |
| Write `IceCubesApp/PrivacyInfo.xcprivacy` (XML below)      | ✅     |
| Local commit `6a87a8d5` on the fork                        | ✅     |
| Push branch to `origin` (the fork)                         | ❌     |
| Open PR against `Dimillian/IceCubesApp:main`               | ❌     |

The fork exists publicly (forking is a non-destructive low-noise action) but
the branch and PR are not visible. Reviewing the local commit, pushing,
and opening the PR are the next session's first steps.

## Resume commands

```bash
cd /tmp/pl-pr/IceCubesApp
git log --oneline -2   # confirm 6a87a8d5 is HEAD
cat IceCubesApp/PrivacyInfo.xcprivacy   # final review
git push -u origin add-privacy-manifest

gh pr create \
  --repo Dimillian/IceCubesApp \
  --base main \
  --head Neelagiri65:add-privacy-manifest \
  --title "Add PrivacyInfo.xcprivacy declaring NSPrivacyAccessedAPICategoryUserDefaults" \
  --body-file /Users/srinathprasannancs/devtools/privacylint/dist/launch/icecubes-pr-body.md
```

## Why this PR (the investigation, for the maintainer)

PrivacyLint flagged 1 ITMS-91053 blocking error and 19 Required-Reason warnings
when scanning IceCubesApp. **Manual triage on each warning site** produced this
narrower fix:

### Real usages (need declaration)

- `Packages/Env/Sources/Env/UserPreferences.swift:88` — `UserDefaults.standard`
  in the production translate-type pathway. Needs `CA92.1` (same-app data).
- `Packages/Env/Sources/Env/UserPreferences.swift:109` — `UserDefaults(suiteName: "group.com.thomasricouard.IceCubesApp")`,
  shared with the widget/notification extensions. Needs `1C8F.1` (same-app-group data).
- `IceCubesApp/App/Main/IceCubesApp.swift:42` — `UserDefaults.standard.register(defaults: …)`,
  inside `#if DEBUG`. Wouldn't ship in release, but covered by CA92.1 anyway.

### Confirmed false positives (NOT included in the PR)

All 14 `creationDate` warnings PrivacyLint flagged are SwiftData `@Model`
property names (`LocalTimeline.creationDate`, `Draft.creationDate`,
`TagGroup.creationDate`), not calls to `URLResourceValues.creationDate`. The
`NSPrivacyAccessedAPICategoryFileTimestamp` category does not apply to this
codebase. Documented as a v1 limitation in PrivacyLint
(no semantic type resolution); fix is on the v0.2.0 roadmap.

### Out of scope for this PR

Extension targets (`IceCubesActionExtension`, `IceCubesShareExtension`,
`IceCubesNotifications`, `IceCubesAppWidgetsExtension`) import `Env` and
therefore transitively use `UserDefaults`. They may need their own
`PrivacyInfo.xcprivacy` copies — flagged in the PR description so the
maintainer can decide.

## The manifest itself

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
                <string>1C8F.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```
