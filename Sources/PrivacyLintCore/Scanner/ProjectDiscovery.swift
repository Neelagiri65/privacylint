import Foundation

/// Walks a project directory and populates a ``ScanContext`` with discovered files.
///
/// v1 limitations:
/// - Test target detection is convention-based (directories matching `*Tests` or
///   `*UITests`). Accurate for SPM layout; approximate for Xcode projects where
///   true membership lives in `.pbxproj`.
/// - Objective-C files are collected into `objcFiles` but not AST-parsed (SwiftSyntax
///   is Swift-only). They are available for future grep-based checks.
public enum ProjectDiscovery {

    private static let excludedDirectoryNames: Set<String> = [
        ".build", "DerivedData", "Pods", "Carthage",
        ".git", ".swiftpm", ".claude",
        "fastlane", "website",
    ]

    private static let dependencyManifestNames: Set<String> = [
        "Package.swift", "Podfile",
    ]

    public static func discover(at projectPath: URL) throws -> ScanContext {
        var swiftProduction: [URL] = []
        var swiftTest: [URL] = []
        var objc: [URL] = []
        var dependencyManifests: [URL] = []
        var privacyManifests: [URL] = []

        let resolvedRoot = projectPath.resolvingSymlinksInPath()
        let rootComponents = resolvedRoot.standardizedFileURL.pathComponents

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectPath,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ScanContext(projectPath: projectPath)
        }

        for case let fileURL as URL in enumerator {
            let resolvedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            let allComponents = resolvedURL.pathComponents
            let relativeComponents = Array(allComponents.dropFirst(rootComponents.count))

            if shouldExclude(relativeComponents: relativeComponents, fileName: fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }

            let fileName = fileURL.lastPathComponent
            let ext = fileURL.pathExtension

            if dependencyManifestNames.contains(fileName) {
                dependencyManifests.append(fileURL)
                continue
            }

            if fileName == "PrivacyInfo.xcprivacy" {
                privacyManifests.append(fileURL)
                continue
            }

            switch ext {
            case "swift":
                if isTestPath(relativeComponents) {
                    swiftTest.append(fileURL)
                } else {
                    swiftProduction.append(fileURL)
                }
            case "m", "h":
                objc.append(fileURL)
            default:
                break
            }
        }

        return ScanContext(
            projectPath: projectPath,
            sourceFiles: swiftProduction.sorted { $0.path < $1.path },
            testFiles: swiftTest.sorted { $0.path < $1.path },
            objcFiles: objc.sorted { $0.path < $1.path },
            dependencyManifests: dependencyManifests.sorted { $0.path < $1.path },
            privacyManifests: privacyManifests.sorted { $0.path < $1.path }
        )
    }

    private static func shouldExclude(relativeComponents: [String], fileName: String) -> Bool {
        for component in relativeComponents.dropLast() {
            if excludedDirectoryNames.contains(component) { return true }
        }
        if excludedDirectoryNames.contains(fileName) { return true }
        if fileName.hasPrefix(".") { return true }
        if fileName.hasSuffix(".xcodeproj") || fileName.hasSuffix(".xcworkspace") { return true }
        return false
    }

    private static func isTestPath(_ relativeComponents: [String]) -> Bool {
        return relativeComponents.dropLast().contains { dir in
            dir.hasSuffix("Tests") || dir.hasSuffix("UITests")
        }
    }
}
