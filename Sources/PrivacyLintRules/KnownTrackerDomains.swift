import Foundation

/// A known tracking domain plus the network or product it belongs to.
///
/// Apex hostnames only. Match logic in TrackingDomainChecker treats subdomains
/// (`connect.facebook.net`, `www.googletagmanager.com`) as matches of the apex
/// via host-suffix comparison.
public struct KnownTrackerDomain: Sendable, Equatable {
    public let host: String
    public let network: String
    public init(host: String, network: String) {
        self.host = host
        self.network = network
    }
}

/// The catalogue of known tracking domains.
///
/// Seed list — representative of the networks indie iOS/macOS devs most
/// commonly integrate. Apple's review uses a larger internal list; we update
/// monthly. Adding a domain here is the v1 path; v2 will fetch from a hosted
/// rules feed.
///
/// Last reviewed: 2026-06.
public enum KnownTrackerDomains {
    public static let all: [KnownTrackerDomain] = [
        // Meta
        .init(host: "facebook.com",          network: "Meta"),
        .init(host: "facebook.net",          network: "Meta"),
        .init(host: "fbcdn.net",             network: "Meta"),
        .init(host: "fb.com",                network: "Meta"),
        // Google
        .init(host: "google-analytics.com",  network: "Google Analytics"),
        .init(host: "analytics.google.com",  network: "Google Analytics"),
        .init(host: "googletagmanager.com",  network: "Google Tag Manager"),
        .init(host: "doubleclick.net",       network: "Google DoubleClick"),
        .init(host: "google-syndication.com",network: "Google AdSense"),
        // Mobile analytics / attribution
        .init(host: "appsflyer.com",         network: "AppsFlyer"),
        .init(host: "adjust.com",            network: "Adjust"),
        .init(host: "branch.io",             network: "Branch"),
        .init(host: "kochava.com",           network: "Kochava"),
        .init(host: "singular.net",          network: "Singular"),
        // Product analytics
        .init(host: "mixpanel.com",          network: "Mixpanel"),
        .init(host: "amplitude.com",         network: "Amplitude"),
        .init(host: "segment.com",           network: "Segment"),
        .init(host: "segment.io",            network: "Segment"),
        .init(host: "heap.io",               network: "Heap"),
        .init(host: "posthog.com",           network: "PostHog"),
        // Crash / error
        .init(host: "sentry.io",             network: "Sentry"),
        .init(host: "bugsnag.com",           network: "Bugsnag"),
        .init(host: "datadoghq.com",         network: "Datadog"),
        // Other ad networks
        .init(host: "applovin.com",          network: "AppLovin"),
        .init(host: "unityads.unity3d.com",  network: "Unity Ads"),
        .init(host: "chartboost.com",        network: "Chartboost"),
        .init(host: "tapjoy.com",            network: "Tapjoy"),
        .init(host: "ironsrc.mobi",          network: "ironSource"),
        .init(host: "vungle.com",            network: "Vungle"),
        // Session replay
        .init(host: "fullstory.com",         network: "FullStory"),
        .init(host: "logrocket.com",         network: "LogRocket"),
    ]

    /// Index by apex hostname for direct lookup.
    public static let byHost: [String: KnownTrackerDomain] = {
        var m: [String: KnownTrackerDomain] = [:]
        for entry in all { m[entry.host] = entry }
        return m
    }()

    /// Match an observed host against the catalogue. Exact apex match or
    /// suffix match against an apex (`connect.facebook.net` → `facebook.net`).
    public static func match(host raw: String) -> KnownTrackerDomain? {
        let host = raw.lowercased()
        if let direct = byHost[host] { return direct }
        for entry in all where host.hasSuffix("." + entry.host) { return entry }
        return nil
    }
}
