import Foundation
import FoundationModels

// MARK: - Provider Protocol

protocol LLMProvider: Sendable {
    var name: String { get }
    func complete(systemPrompt: String, userMessage: String) async throws -> String
}

enum LLMProviderError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Set your API key in Settings."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .httpError(let code, let body):
            return Self.describeHTTPError(code: code, body: body)
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    private static func describeHTTPError(code: Int, body: String) -> String {
        let parsed = parseAPIError(body)
        switch code {
        case 401:
            return "Authentication failed (HTTP 401). \(parsed ?? "Check that your API key is correct and from console.anthropic.com (not claude.ai).")"
        case 403:
            return "Access denied (HTTP 403). \(parsed ?? "Your API key may lack permissions.")"
        case 429:
            return "Rate limited (HTTP 429). \(parsed ?? "You may need to add credits at console.anthropic.com/settings/billing.")"
        case 400:
            return "Bad request (HTTP 400). \(parsed ?? String(body.prefix(200)))"
        case 404:
            return "Model not found (HTTP 404). \(parsed ?? "The selected model may not be available on your plan.")"
        case 500...599:
            return "Server error (HTTP \(code)). Try again in a moment."
        default:
            return "HTTP \(code): \(parsed ?? String(body.prefix(200)))"
        }
    }

    /// Extract the "message" field from an Anthropic/OpenAI API error JSON body.
    private static func parseAPIError(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}

// MARK: - Anthropic Provider

struct AnthropicProvider: LLMProvider {
    let name = "Anthropic (Claude)"
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.model = model
    }

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw LLMProviderError.invalidResponse
        }

        return text
    }
}

// MARK: - OpenAI-Compatible Provider

struct OpenAICompatibleProvider: LLMProvider {
    let name: String
    let apiKey: String
    let baseURL: String
    let model: String

    init(name: String = "OpenAI-Compatible", apiKey: String, baseURL: String, model: String = "gpt-4o") {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.model = model
    }

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        let endpoint = "\(baseURL)/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw LLMProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMProviderError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMProviderError.invalidResponse
        }

        return text
    }
}

// MARK: - Apple On-Device Provider (Foundation Models)

@available(macOS 26.0, *)
struct OnDeviceProvider: LLMProvider {
    let name = "Apple On-Device"

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        let model = SystemLanguageModel.default

        guard model.isAvailable else {
            switch model.availability {
            case .unavailable(.deviceNotEligible):
                throw OnDeviceProviderError.deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                throw OnDeviceProviderError.appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                throw OnDeviceProviderError.modelNotReady
            default:
                throw OnDeviceProviderError.unavailable
            }
        }

        let session = LanguageModelSession(instructions: systemPrompt)

        // On-device model has a 4096-token context (~12K chars).
        // Truncate input to fit within context alongside instructions and response.
        let maxInputChars = 8000
        let truncatedMessage: String
        if userMessage.count > maxInputChars {
            truncatedMessage = String(userMessage.prefix(maxInputChars)) + "\n\n[Document truncated due to length. Extract what you can from the text above.]"
        } else {
            truncatedMessage = userMessage
        }

        let response = try await session.respond(to: truncatedMessage)
        return response.content
    }

    /// Check if the on-device model is available on this machine.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static var unavailableReason: String? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled. Enable it in System Settings > Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        @unknown default:
            return "On-device model is unavailable."
        }
    }
}

@available(macOS 26.0, *)
enum OnDeviceProviderError: LocalizedError {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            return "This Mac doesn't support Apple Intelligence. Use a cloud provider instead."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Enable it in System Settings > Apple Intelligence & Siri."
        case .modelNotReady:
            return "The on-device model is still downloading. Please try again in a few minutes."
        case .unavailable:
            return "On-device model is not available. Use a cloud provider instead."
        }
    }
}

// MARK: - Provider Factory

enum LLMProviderFactory {
    static func create() -> LLMProvider? {
        let settings = AppSettings.shared

        switch settings.selectedProvider {
        case "ondevice":
            if #available(macOS 26.0, *) {
                return OnDeviceProvider()
            }
            return nil

        case "anthropic":
            guard let keyData = try? KeychainHelper.load(account: "llm-api-key"),
                  let key = String(data: keyData, encoding: .utf8), !key.isEmpty else {
                return nil
            }
            return AnthropicProvider(apiKey: key)

        case "openai-compatible":
            guard let keyData = try? KeychainHelper.load(account: "llm-api-key"),
                  let key = String(data: keyData, encoding: .utf8), !key.isEmpty else {
                return nil
            }
            let baseURL = settings.llmBaseURL.isEmpty ? "https://api.openai.com" : settings.llmBaseURL
            return OpenAICompatibleProvider(apiKey: key, baseURL: baseURL)

        default:
            return nil
        }
    }

    /// Whether the on-device provider is available on this system.
    static var onDeviceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return OnDeviceProvider.isAvailable
        }
        return false
    }

    static var onDeviceUnavailableReason: String? {
        if #available(macOS 26.0, *) {
            return OnDeviceProvider.unavailableReason
        }
        return "Requires macOS 26 or later."
    }
}
