# typed: false
# frozen_string_literal: true

# PrivacyLint Homebrew formula.
#
# This file lives in the TAP repo: github.com/Neelagiri65/homebrew-privacylint
# Path inside that repo: Formula/privacylint.rb
#
# Users install with:
#   brew tap Neelagiri65/privacylint
#   brew install privacylint
#
# Releasing a new version:
#   1. Tag the privacylint repo (e.g. `git tag v0.1.1 && git push origin v0.1.1`).
#   2. `gh release create v0.1.1 --generate-notes` in the privacylint repo.
#   3. Compute the tarball SHA: `shasum -a 256 <(curl -sL <tarball-url>)`.
#   4. Bump `url`, `sha256`, and the test version-assert below in this file.
#   5. Commit and push the tap repo.
class Privacylint < Formula
  desc "Catch every App Store privacy rejection before you hit submit"
  homepage "https://github.com/Neelagiri65/privacylint"
  url "https://github.com/Neelagiri65/privacylint/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_AFTER_RELEASE"
  license "MIT"
  head "https://github.com/Neelagiri65/privacylint.git", branch: "master"

  # PrivacyLint depends on SwiftSyntax 603.x which requires the Swift 6.3
  # toolchain (ships with Xcode 26). Older Xcodes will fail at build time
  # with a clear swift-syntax compatibility error.
  depends_on xcode: ["16.0", :build]

  def install
    system "swift", "build",
           "--disable-sandbox",
           "--configuration", "release",
           "--product", "privacylint"
    bin.install ".build/release/privacylint"
  end

  test do
    # Smoke: the binary runs, prints its version, and exits 0.
    assert_match(/0\.\d+\.\d+/, shell_output("#{bin}/privacylint --version"))

    # Real run: create a tiny SPM project that uses a Required-Reason API
    # without a manifest, and verify PrivacyLint detects the violation and
    # exits non-zero. This is the CI contract — if it ever regresses,
    # `brew test privacylint` fails before publication.
    (testpath/"Package.swift").write <<~SWIFT
      // swift-tools-version:5.9
      import PackageDescription
      let package = Package(
        name: "Demo",
        platforms: [.iOS(.v17)],
        targets: [.executableTarget(name: "App", path: "Sources/App")]
      )
    SWIFT
    (testpath/"Sources/App").mkpath
    (testpath/"Sources/App/main.swift").write <<~SWIFT
      import Foundation
      let v = UserDefaults.standard.bool(forKey: "k")
      _ = v
    SWIFT

    output = shell_output("#{bin}/privacylint --path #{testpath} --format json --no-color", 1)
    assert_match "required-reason-api", output
    assert_match "ITMS-91053", output
  end
end
