import Foundation

/// A category of Apple "Required Reason" API together with its approved reason
/// codes and the source-level symbols that indicate its use.
///
/// This is intentionally a plain data table so the rule set can be refreshed
/// monthly as Apple updates its requirements.
public struct RequiredReasonAPI: Sendable, Equatable {
    /// The privacy-manifest category, e.g. `NSPrivacyAccessedAPICategoryUserDefaults`.
    public let category: String
    /// A short, human-readable name (British English).
    public let displayName: String
    /// Approved reason codes, e.g. `["CA92.1", "1C8F.1"]`.
    public let approvedReasons: [String]
    /// Symbols whose use triggers the requirement, e.g. `["UserDefaults"]`.
    public let triggeringSymbols: [String]

    public init(category: String, displayName: String, approvedReasons: [String], triggeringSymbols: [String]) {
        self.category = category
        self.displayName = displayName
        self.approvedReasons = approvedReasons
        self.triggeringSymbols = triggeringSymbols
    }
}

/// The catalogue of Required Reason APIs.
///
/// Source: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
/// Last reviewed: 2026-06 (update monthly).
public enum RequiredReasonAPIs {
    public static let all: [RequiredReasonAPI] = [
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryFileTimestamp",
            displayName: "File timestamp APIs",
            approvedReasons: ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
            triggeringSymbols: ["creationDate", "modificationDate", "fileModificationDate", "contentModificationDateKey", "creationDateKey"]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategorySystemBootTime",
            displayName: "System boot time APIs",
            approvedReasons: ["35F9.1", "8FFB.1", "3D61.1"],
            triggeringSymbols: ["systemUptime", "mach_absolute_time"]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryDiskSpace",
            displayName: "Disk space APIs",
            approvedReasons: ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
            triggeringSymbols: ["volumeAvailableCapacityKey", "volumeAvailableCapacityForImportantUsageKey", "systemFreeSize", "systemSize"]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryActiveKeyboards",
            displayName: "Active keyboard APIs",
            approvedReasons: ["3EC4.1", "54BD.1"],
            triggeringSymbols: ["activeInputModes"]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryUserDefaults",
            displayName: "User defaults APIs",
            approvedReasons: ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
            triggeringSymbols: ["UserDefaults"]
        )
    ]
}
