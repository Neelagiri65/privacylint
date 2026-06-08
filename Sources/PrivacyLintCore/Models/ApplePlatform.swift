import Foundation

/// The Apple platforms PrivacyLint reasons about when deciding which checks
/// apply to a project.
///
/// Why this exists: macOS apps need a `PrivacyInfo.xcprivacy` file but are
/// exempt from declaring Required-Reason API usage. Every other Apple
/// platform must declare it. A scanner that flags `UserDefaults.standard`
/// in a macOS-only project is a false positive — the kind that erodes a
/// developer's trust in the tool. Threading this through the pipeline
/// means we report the truth per target, not a generic "iOS" assumption.
public enum ApplePlatform: String, Sendable, Codable, CaseIterable, Hashable {
    case iOS
    case iPadOS
    case tvOS
    case watchOS
    case visionOS
    case macOS
    case macCatalyst

    /// Whether the platform requires declaring Required-Reason API usage
    /// (`NSPrivacyAccessedAPITypes`) in `PrivacyInfo.xcprivacy`.
    ///
    /// macOS is the sole exemption (Apple, Privacy manifest files). Mac
    /// Catalyst is iOS-derived and follows iOS rules.
    public var requiresRequiredReasonAPI: Bool {
        switch self {
        case .iOS, .iPadOS, .tvOS, .watchOS, .visionOS, .macCatalyst:
            return true
        case .macOS:
            return false
        }
    }

    /// Whether the platform requires a `PrivacyInfo.xcprivacy` file at all.
    ///
    /// Every App-Store-distributed platform does.
    public var requiresPrivacyManifest: Bool { true }

    /// Map the lowercase name `swift package describe --type json` emits
    /// (`ios`, `macos`, `tvos`, `watchos`, `visionos`, `maccatalyst`,
    /// `driverkit`) to an `ApplePlatform`. Unknown names return `nil` and
    /// are logged by the caller — silent drops would hide real targets.
    public static func fromSPMName(_ raw: String) -> ApplePlatform? {
        switch raw.lowercased() {
        case "ios":         return .iOS
        case "ipados":      return .iPadOS
        case "tvos":        return .tvOS
        case "watchos":     return .watchOS
        case "visionos":    return .visionOS
        case "macos":       return .macOS
        case "maccatalyst": return .macCatalyst
        default:            return nil
        }
    }
}
