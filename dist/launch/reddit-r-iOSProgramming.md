## Title

**I built a CLI that catches ITMS-91053 and related App Store privacy rejections before you submit — and ran it on IceCubesApp as a smoke test**

## Body

ITMS-91053 ("Missing API declaration") has been the fastest-growing App Store rejection category since May 2024 — and the existing tooling is either dead OSS scripts that haven't been updated for the 2025-2026 rules, or enterprise platforms that don't price for indie devs. The new wave (Oxbit Preflight etc.) covers more breadth but skims privacy.

So I built **PrivacyLint** — an open-source Swift CLI that does AST-level scanning for the five things App Review will actually reject you for:

- `ITMS-91053` — Required Reason APIs used without a declared reason in `PrivacyInfo.xcprivacy`
- `ITMS-91061` — third-party SDKs (Firebase, nanopb, Realm, etc.) missing their own privacy manifest, including transitively
- Undeclared tracking domains (Meta Pixel, Google Tag Manager, Mixpanel, AppsFlyer, Adjust, Branch, Sentry, etc.) vs `NSPrivacyTrackingDomains`
- AI service calls (OpenAI, Anthropic, Google AI, Mistral, Cohere) without a consent surface — Apple's November 2025 guidance, nobody else checks this
- Platform-aware: macOS-only targets correctly skip the Required-Reason section (macOS is exempt from that one)

It uses SwiftSyntax for the AST work, so it doesn't false-positive on the same comment/string-literal/test-target traps the grep-based tools do. CI-ready (exits 1 on errors). Coloured terminal output. ~120 tests behind it.

### Smoke test on a real app

To prove this isn't a synthetic-fixture-only tool, I ran it on **IceCubesApp** (Dimillian's Mastodon client — popular open-source SwiftUI app).

Result: **1 ITMS-91053 blocking error + 19 Required-Reason warnings** across 12 files.

```
[privacy-manifest-validation] Privacy manifest validation
✗ failed · 1 error

    error  IceCubesApp/App/Main/AppView.swift:36:31
           Your project uses Required Reason APIs
           (NSPrivacyAccessedAPICategoryFileTimestamp,
           NSPrivacyAccessedAPICategoryUserDefaults) but contains no
           PrivacyInfo.xcprivacy. App Review will reject this with ITMS-91053.
           fix-it: Add a PrivacyInfo.xcprivacy file to your main bundle and
           declare an NSPrivacyAccessedAPITypes entry for each category listed
           above.
```

I checked — there's no `PrivacyInfo.xcprivacy` anywhere in the IceCubesApp repo. Real finding. [PR open here.](https://github.com/Dimillian/IceCubesApp/pull/2471)

Honest caveat from the same run: some of the 19 Required-Reason warnings are `creationDate`/`modificationDate` on SwiftData `@Attribute` declarations, which v1 can't disambiguate from a real `URL.creationDate` call — semantic type resolution is on the v2 roadmap. Each one is flagged with file and line for review.

### Install

```bash
brew tap Neelagiri65/privacylint
brew install privacylint
privacylint --path /path/to/your/project
```

GitHub Actions:

```yaml
- name: PrivacyLint
  run: privacylint --path . --format terminal
```

### Links

- Source: https://github.com/Neelagiri65/privacylint (MIT)
- Blog post explaining ITMS-91053 + manual fix + traps: [link once published]
- Found an SDK PrivacyLint missed? Open an issue with the SDK name and Package.resolved line: https://github.com/Neelagiri65/privacylint/issues — crowdsourced matching keeps the catalogue current.

Happy to answer questions about the AST work, the matrix-as-spec approach, or the AI-consent heuristics specifically.
