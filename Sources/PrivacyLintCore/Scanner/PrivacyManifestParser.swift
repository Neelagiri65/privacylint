import Foundation

/// Parses a `PrivacyInfo.xcprivacy` file into a typed ``PrivacyManifest``.
///
/// `PrivacyInfo.xcprivacy` is a property list (binary or XML — Apple's docs
/// say both are valid). Foundation's `PropertyListSerialization` handles both
/// formats transparently.
public enum PrivacyManifestParser {
    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case unreadable(URL, String)
        case notADictionary(URL)
        case malformedAccessedAPIEntry(URL)

        public var description: String {
            switch self {
            case .unreadable(let url, let reason):
                return "could not read \(url.lastPathComponent): \(reason)"
            case .notADictionary(let url):
                return "\(url.lastPathComponent) is not a dictionary at the root"
            case .malformedAccessedAPIEntry(let url):
                return "\(url.lastPathComponent) contains an NSPrivacyAccessedAPIType entry without the expected keys"
            }
        }
    }

    public static func parse(at url: URL) throws -> PrivacyManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ParseError.unreadable(url, error.localizedDescription)
        }
        return try parse(data: data, fileURL: url)
    }

    /// Test-friendly entry point. Skips file IO.
    public static func parse(data: Data, fileURL: URL) throws -> PrivacyManifest {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw ParseError.unreadable(fileURL, error.localizedDescription)
        }
        guard let dict = plist as? [String: Any] else {
            throw ParseError.notADictionary(fileURL)
        }

        let tracking = dict["NSPrivacyTracking"] as? Bool ?? false
        let trackingDomains = dict["NSPrivacyTrackingDomains"] as? [String] ?? []

        var accessedAPITypes: [AccessedAPIType] = []
        if let raw = dict["NSPrivacyAccessedAPITypes"] as? [[String: Any]] {
            for entry in raw {
                guard let category = entry["NSPrivacyAccessedAPIType"] as? String else {
                    throw ParseError.malformedAccessedAPIEntry(fileURL)
                }
                let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
                accessedAPITypes.append(AccessedAPIType(apiCategory: category, reasons: reasons))
            }
        }

        var collected: [CollectedDataType] = []
        if let raw = dict["NSPrivacyCollectedDataTypes"] as? [[String: Any]] {
            for entry in raw {
                guard let type = entry["NSPrivacyCollectedDataType"] as? String else { continue }
                let linked = entry["NSPrivacyCollectedDataTypeLinked"] as? Bool ?? false
                let tracking = entry["NSPrivacyCollectedDataTypeTracking"] as? Bool ?? false
                let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
                collected.append(
                    CollectedDataType(type: type, linked: linked, tracking: tracking, purposes: purposes)
                )
            }
        }

        return PrivacyManifest(
            tracking: tracking,
            trackingDomains: trackingDomains,
            collectedDataTypes: collected,
            accessedAPITypes: accessedAPITypes
        )
    }
}
