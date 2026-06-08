import Foundation

/// Apple's list of commonly-used third-party SDKs that must ship a signed
/// privacy manifest.
///
/// Source: https://developer.apple.com/support/third-party-SDK-requirements/
/// Last reviewed: 2026-06 (update monthly).
public enum ThirdPartySDKList {
    /// Map a dependency identity (SPM `identity` string or CocoaPods name) to
    /// Apple's canonical SDK name if it matches one. Returns `nil` when the
    /// dependency is not on Apple's required-manifest list.
    ///
    /// Identities differ from display names — SPM repos are usually
    /// kebab-case (`firebase-ios-sdk`), Pods are PascalCase (`Firebase`).
    /// Both should match the canonical `Firebase` entry. We normalise both
    /// sides (lowercase, strip `-ios-sdk` / `-swift` / `-ios` suffixes,
    /// drop dashes and slashes) and look up directly. Substring matching is
    /// deliberately avoided — too aggressive, easy to false-positive.
    public static func match(identity: String) -> String? {
        let key = normalise(identity)
        return normalisedIndex[key]
    }

    /// Test/diagnostic helper.
    public static func normalise(_ s: String) -> String {
        var n = s.lowercased()
        // Strip Apple-flavour SPM suffixes BEFORE removing dashes. Note we
        // do NOT strip `-swift` — Apple's SDK names include "Swift" as a
        // meaningful part (RealmSwift, RxSwift, IQKeyboardManagerSwift),
        // so stripping would drop real matches like `realm-swift → realm`
        // that no longer match the canonical `RealmSwift` entry.
        for suffix in ["-ios-sdk", "-ios-spm", "-swift-package", "-ios", "-cocoa"] {
            if n.hasSuffix(suffix) { n.removeLast(suffix.count) }
        }
        n.removeAll { $0 == "-" || $0 == "_" || $0 == " " || $0 == "/" }
        return n
    }

    /// Pre-computed `normalised → canonical` index for O(1) match.
    private static let normalisedIndex: [String: String] = {
        var m: [String: String] = [:]
        for name in required {
            m[normalise(name)] = name
        }
        return m
    }()


    /// Canonical SDK names as published by Apple.
    public static let required: Set<String> = [
        "Abseil",
        "AFNetworking",
        "Alamofire",
        "AppAuth",
        "BoringSSL / openssl_grpc",
        "Capacitor",
        "Charts",
        "connectivity_plus",
        "Cordova",
        "device_info_plus",
        "DKImagePickerController",
        "DKPhotoGallery",
        "FBAEMKit",
        "FBLPromises",
        "FBSDKCoreKit",
        "Firebase",
        "FirebaseABTesting",
        "FirebaseAuth",
        "FirebaseCore",
        "FirebaseCrashlytics",
        "FirebaseInstallations",
        "FirebaseMessaging",
        "FirebaseRemoteConfig",
        "Flutter",
        "fluttertoast",
        "FMDB",
        "geolocator_apple",
        "GoogleDataTransport",
        "GoogleSignIn",
        "GoogleToolboxForMac",
        "GoogleUtilities",
        "grpcpp",
        "GTMAppAuth",
        "GTMSessionFetcher",
        "hermes",
        "image_picker_ios",
        "IQKeyboardManager",
        "IQKeyboardManagerSwift",
        "Kingfisher",
        "leveldb",
        "Lottie",
        "MBProgressHUD",
        "nanopb",
        "OneSignal",
        "OneSignalCore",
        "OpenSSL",
        "OrderedSet",
        "package_info",
        "package_info_plus",
        "path_provider",
        "path_provider_ios",
        "Promises",
        "Protobuf",
        "Reachability",
        "RealmSwift",
        "RxCocoa",
        "RxRelay",
        "RxSwift",
        "SDWebImage",
        "share_plus",
        "shared_preferences_ios",
        "SnapKit",
        "sqflite",
        "Starscream",
        "SVProgressHUD",
        "SwiftyGif",
        "SwiftyJSON",
        "Toast",
        "UnityFramework",
        "url_launcher",
        "url_launcher_ios",
        "video_player_avfoundation",
        "wakelock",
        "webview_flutter_wkwebview"
    ]
}
