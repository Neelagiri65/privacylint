import Foundation

/// An in-memory model of a `PrivacyInfo.xcprivacy` manifest.
///
/// This mirrors the keys Apple defines for privacy manifests. The parser that
/// populates it from disk is implemented in a later step.
public struct PrivacyManifest: Codable, Sendable, Equatable {
    /// Corresponds to `NSPrivacyTracking`.
    public var tracking: Bool
    /// Corresponds to `NSPrivacyTrackingDomains`.
    public var trackingDomains: [String]
    /// Corresponds to `NSPrivacyCollectedDataTypes`.
    public var collectedDataTypes: [CollectedDataType]
    /// Corresponds to `NSPrivacyAccessedAPITypes`.
    public var accessedAPITypes: [AccessedAPIType]

    public init(
        tracking: Bool = false,
        trackingDomains: [String] = [],
        collectedDataTypes: [CollectedDataType] = [],
        accessedAPITypes: [AccessedAPIType] = []
    ) {
        self.tracking = tracking
        self.trackingDomains = trackingDomains
        self.collectedDataTypes = collectedDataTypes
        self.accessedAPITypes = accessedAPITypes
    }
}

/// A declared collected data type (`NSPrivacyCollectedDataType`).
public struct CollectedDataType: Codable, Sendable, Equatable {
    public let type: String
    public let linked: Bool
    public let tracking: Bool
    public let purposes: [String]

    public init(type: String, linked: Bool, tracking: Bool, purposes: [String]) {
        self.type = type
        self.linked = linked
        self.tracking = tracking
        self.purposes = purposes
    }
}

/// A declared Required Reason API access (`NSPrivacyAccessedAPIType`).
public struct AccessedAPIType: Codable, Sendable, Equatable {
    /// e.g. `NSPrivacyAccessedAPICategoryUserDefaults`.
    public let apiCategory: String
    /// The declared reason codes, e.g. `["CA92.1"]`.
    public let reasons: [String]

    public init(apiCategory: String, reasons: [String]) {
        self.apiCategory = apiCategory
        self.reasons = reasons
    }
}
