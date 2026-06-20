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

    init(apiKey: String, model: String = "claude-sonnet-4-6") {
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
@Generable
struct OnDeviceLineItem {
    @Guide(description: "Transaction date in YYYY-MM-DD format")
    var date: String

    @Guide(description: "Vendor or merchant name")
    var vendor: String

    @Guide(description: "Brief description of the charge or transaction")
    var description: String

    @Guide(description: "Dollar amount: positive for charges and costs, negative for refunds and credits")
    var amount: Double

    @Guide(description: "One of: Housing, Utilities, Groceries, Dining, Transportation, Entertainment, Subscriptions, Healthcare, Insurance, Shopping, Travel, Education, Personal Care, Gifts, Fees & Charges, Other")
    var category: String

    @Guide(description: "Consumption quantity for utility items such as kWh or therms")
    var quantity: Double?

    @Guide(description: "Unit of consumption: kWh, therms, CCF, gallons, or cuft")
    var unit: String?
}

@available(macOS 26.0, *)
@Generable
struct OnDeviceDocumentResult {
    @Guide(description: "One of: credit_card_statement, receipt, utility_bill, bank_statement, other")
    var documentType: String

    @Guide(description: "Statement period start date in YYYY-MM-DD format")
    var periodStart: String?

    @Guide(description: "Statement period end date in YYYY-MM-DD format")
    var periodEnd: String?

    @Guide(description: "Individual charges, transactions, or line items from the document")
    var lineItems: [OnDeviceLineItem]
}

@available(macOS 26.0, *)
struct OnDeviceProvider: LLMProvider {
    let name = "Apple On-Device"

    private func ensureAvailable() throws {
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
    }

    private func truncate(_ text: String, maxChars: Int = 8000) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars))
    }

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        try ensureAvailable()

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: truncate(userMessage))
        return response.content
    }

    func parseDocument(text: String) async throws -> OnDeviceDocumentResult {
        try ensureAvailable()

        let instructions = """
            Extract financial data from this document. Identify every individual \
            charge, transaction, or line item with its date, vendor, dollar amount, \
            and category. Charges and bills the user owes are positive amounts. \
            Refunds, credits, and cashback are negative amounts. For utility bills \
            (electricity, gas, water), also extract consumption quantity and unit.
            """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: truncate(text),
            generating: OnDeviceDocumentResult.self
        )
        return response.content
    }

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
            return AnthropicProvider(apiKey: key, model: settings.selectedModel)

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
