# homebrew-privacylint

Homebrew tap for [PrivacyLint](https://github.com/Neelagiri65/privacylint) — a
Swift CLI that scans iOS/macOS Xcode projects for App Store privacy compliance
issues and catches every `ITMS-91053` / `ITMS-91061` rejection before you hit
submit.

## Install

```bash
brew tap Neelagiri65/privacylint
brew install privacylint
```

## Use

```bash
privacylint --path /path/to/your/xcode/project
```

The CLI exits **1** when at least one error is found, so it drops straight into
CI without extra plumbing. See the
[main repo README](https://github.com/Neelagiri65/privacylint#ci-integration)
for GitHub Actions / Xcode build phase / pre-commit hook examples.

## Upgrade

```bash
brew update
brew upgrade privacylint
```

## Issues

Bug reports and SDK-list omissions: the main repo at
<https://github.com/Neelagiri65/privacylint/issues>. Formula bugs (build
breaks, missing deps): file here.
