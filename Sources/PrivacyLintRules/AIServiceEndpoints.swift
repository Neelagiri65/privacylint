import Foundation

/// A known external AI/LLM service whose use triggers Apple's AI consent
/// requirement (in force since November 2025).
public struct AIServiceEndpoint: Sendable, Equatable {
    /// The provider's name, e.g. `"OpenAI"`.
    public let provider: String
    /// Host names that indicate a call to the service.
    public let hosts: [String]
    /// SDK/package names that indicate integration.
    public let packages: [String]

    public init(provider: String, hosts: [String], packages: [String]) {
        self.provider = provider
        self.hosts = hosts
        self.packages = packages
    }
}

/// The catalogue of known AI service endpoints.
///
/// Last reviewed: 2026-06 (update monthly).
public enum AIServiceEndpoints {
    public static let known: [AIServiceEndpoint] = [
        AIServiceEndpoint(
            provider: "OpenAI",
            hosts: ["api.openai.com"],
            packages: ["OpenAI", "openai-swift", "MacPaw/OpenAI"]
        ),
        AIServiceEndpoint(
            provider: "Anthropic",
            hosts: ["api.anthropic.com"],
            packages: ["AnthropicSwift", "swift-anthropic"]
        ),
        AIServiceEndpoint(
            provider: "Google AI",
            hosts: ["generativelanguage.googleapis.com", "aiplatform.googleapis.com"],
            packages: ["GoogleGenerativeAI", "generative-ai-swift"]
        ),
        AIServiceEndpoint(
            provider: "Mistral",
            hosts: ["api.mistral.ai"],
            packages: []
        ),
        AIServiceEndpoint(
            provider: "Cohere",
            hosts: ["api.cohere.ai", "api.cohere.com"],
            packages: []
        )
    ]
}
