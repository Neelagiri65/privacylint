// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PrivacyLint",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "privacylint", targets: ["PrivacyLint"]),
        .library(name: "PrivacyLintCore", targets: ["PrivacyLintCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"604.0.0")
    ],
    targets: [
        .executableTarget(
            name: "PrivacyLint",
            dependencies: [
                "PrivacyLintCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "PrivacyLintCore",
            dependencies: [
                "PrivacyLintRules",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .target(
            name: "PrivacyLintRules"
        ),
        .testTarget(
            name: "PrivacyLintCoreTests",
            dependencies: ["PrivacyLintCore"]
        )
    ]
)
