import Foundation
import Testing
@testable import PrivacyLintCore

@Suite("ProjectDiscovery")
struct ProjectDiscoveryTests {
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacylint-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func touch(_ root: URL, _ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Swift source files

    @Test func discoversSwiftSourceFiles() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "Sources/App/main.swift")
        try touch(root, "Views/HomeView.swift")
        try touch(root, "Models/User.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.count == 3)
        #expect(context.testFiles.isEmpty)
    }

    @Test func separatesTestFiles() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "Sources/App/main.swift")
        try touch(root, "Tests/AppTests/AppTests.swift")
        try touch(root, "MyAppUITests/LoginUITests.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.count == 1)
        #expect(context.testFiles.count == 2)
    }

    // MARK: - Objective-C files

    @Test func collectsObjCFilesSeparately() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "Sources/Legacy.m")
        try touch(root, "Sources/Legacy.h")
        try touch(root, "Sources/Modern.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.count == 1)
        #expect(context.objcFiles.count == 2)
    }

    // MARK: - Exclusions

    @Test func excludesBuildArtifacts() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "Sources/App.swift")
        try touch(root, ".build/checkouts/Dep/Source.swift")
        try touch(root, "DerivedData/Build/App.swift")
        try touch(root, "Pods/AFNetworking/Source.swift")
        try touch(root, "Carthage/Checkouts/Lib/Lib.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.count == 1)
        let paths = context.sourceFiles.map(\.lastPathComponent)
        #expect(paths == ["App.swift"])
    }

    @Test func excludesHiddenDirectories() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "Sources/App.swift")
        try touch(root, ".claude/settings.swift")
        try touch(root, ".git/hooks/pre-commit.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.count == 1)
    }

    // MARK: - Dependency manifests

    @Test func findsDependencyManifests() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "Package.swift")
        try touch(root, "Podfile")
        try touch(root, "Sources/App.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.dependencyManifests.count == 2)
        let names = Set(context.dependencyManifests.map(\.lastPathComponent))
        #expect(names == ["Package.swift", "Podfile"])
    }

    // MARK: - Privacy manifests

    @Test func findsPrivacyManifests() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "PrivacyInfo.xcprivacy")
        try touch(root, "MyFramework/PrivacyInfo.xcprivacy")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.privacyManifests.count == 2)
    }

    @Test func privacyManifestsNotInExcludedDirs() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "PrivacyInfo.xcprivacy")
        try touch(root, "Pods/SomeSDK/PrivacyInfo.xcprivacy")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.privacyManifests.count == 1)
    }

    // MARK: - Xcode-style project (flat layout, no Sources/)

    @Test func handlesXcodeProjectLayout() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        try touch(root, "MyApp.xcodeproj/project.pbxproj")
        try touch(root, "AppDelegate.swift")
        try touch(root, "Views/HomeView.swift")
        try touch(root, "Models/User.swift")
        try touch(root, "PrivacyInfo.xcprivacy")
        try touch(root, "MyAppTests/MyAppTests.swift")

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.count == 3)
        #expect(context.testFiles.count == 1)
        #expect(context.privacyManifests.count == 1)
    }

    // MARK: - Empty project

    @Test func emptyProjectReturnsEmptyContext() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.sourceFiles.isEmpty)
        #expect(context.testFiles.isEmpty)
        #expect(context.objcFiles.isEmpty)
        #expect(context.dependencyManifests.isEmpty)
        #expect(context.privacyManifests.isEmpty)
    }

    @Test func projectPathIsSet() throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let context = try ProjectDiscovery.discover(at: root)

        #expect(context.projectPath == root)
    }
}
