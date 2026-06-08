# Release runbook — PrivacyLint

Each release is two coordinated pushes: one tagged GitHub release on
`Neelagiri65/privacylint`, and one Homebrew formula bump on
`Neelagiri65/homebrew-privacylint`. Below are the exact commands for the
first release; subsequent ones follow the same shape with the version
bumped.

Pre-flight (run once, ever):

```bash
# 1. Create the public main repo on GitHub (visible action — confirm first).
gh repo create Neelagiri65/privacylint \
    --public \
    --source . \
    --remote origin \
    --description "Catch every App Store privacy rejection before you hit submit"

# 2. Push everything we have.
git push -u origin master --tags

# 3. Create the tap repo. Convention: the prefix `homebrew-` is required;
#    `brew tap Neelagiri65/privacylint` implicitly resolves it.
gh repo create Neelagiri65/homebrew-privacylint \
    --public \
    --description "Homebrew tap for PrivacyLint"
```

## Cutting v0.1.0

```bash
# Tag is already created locally — push it.
git push origin v0.1.0

# 1. Cut the GitHub release. --generate-notes pulls in commit messages.
gh release create v0.1.0 \
    --title "v0.1.0 — first public release" \
    --generate-notes

# 2. Get the source tarball SHA.
SHA256=$(curl -sL https://github.com/Neelagiri65/privacylint/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256 | awk '{print $1}')
echo "SHA256: $SHA256"

# 3. Clone the tap repo, copy the formula in, fill the SHA, push.
TAP_DIR=$(mktemp -d)
git clone https://github.com/Neelagiri65/homebrew-privacylint "$TAP_DIR"
mkdir -p "$TAP_DIR/Formula"
cp dist/homebrew/privacylint.rb "$TAP_DIR/Formula/privacylint.rb"
cp dist/homebrew/README-tap.md "$TAP_DIR/README.md"
sed -i '' "s/REPLACE_WITH_SHA256_AFTER_RELEASE/$SHA256/" "$TAP_DIR/Formula/privacylint.rb"

cd "$TAP_DIR"
git add Formula/privacylint.rb README.md
git commit -m "privacylint 0.1.0"
git push

# 4. Smoke-test install on a clean shell.
brew untap Neelagiri65/privacylint 2>/dev/null || true
brew tap Neelagiri65/privacylint
brew install privacylint
privacylint --version   # should print: 0.1.0
```

## Cutting subsequent versions

```bash
NEW_VERSION="0.1.1"

# 1. Bump the CLI version string.
sed -i '' "s/version: \"[0-9.]*\"/version: \"$NEW_VERSION\"/" \
    Sources/PrivacyLint/PrivacyLintCommand.swift

# 2. Tag.
git add -A && git commit -m "release: $NEW_VERSION"
git tag "v$NEW_VERSION"
git push && git push --tags

# 3. Cut the release.
gh release create "v$NEW_VERSION" --generate-notes

# 4. Bump the formula's url and sha256.
SHA256=$(curl -sL "https://github.com/Neelagiri65/privacylint/archive/refs/tags/v$NEW_VERSION.tar.gz" | shasum -a 256 | awk '{print $1}')

# 5. Update tap repo (same flow as initial release, just sed both
#    `v0.1.0 → v$NEW_VERSION` and the sha256).
```

## What's left after the tap is live

Per HANDOFF NEXT:
1. ✅ brew tap (this runbook).
2. **`ITMS-91053` blog post.** Title: "ITMS-91053: How to fix Missing API Declaration in your iOS app". Lead with the panic search the developer just made, not the product. Solve their problem first, then reveal PrivacyLint as the way to never see this email again. Distribute on r/iOSProgramming, Indie Dev Monday, Swift Forums.
3. Show HN — once the blog post is live.
4. HTML reporter (post-launch nice-to-have).
5. v2 ASC integration — `privacylint connect validate-against-asc`.
