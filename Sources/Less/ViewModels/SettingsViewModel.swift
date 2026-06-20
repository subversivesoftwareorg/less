import Foundation
import Observation

@Observable final class SettingsViewModel {
    var selectedProvider: String
    var selectedModel: String
    var apiKey: String = ""
    var baseURL: String
    var hasAPIKey: Bool = false
    var validationMessage: String?
    var validationSuccess: Bool = false
    var isValidating = false

    init() {
        let settings = AppSettings.shared
        self.selectedProvider = settings.selectedProvider
        self.selectedModel = settings.selectedModel
        self.baseURL = settings.llmBaseURL
        self.hasAPIKey = KeychainHelper.exists(account: "llm-api-key")
        if let data = try? KeychainHelper.load(account: "llm-api-key"),
           let key = String(data: data, encoding: .utf8) {
            self.apiKey = key
        }
    }

    func saveSettings() {
        let settings = AppSettings.shared
        settings.selectedProvider = selectedProvider
        settings.selectedModel = selectedModel
        settings.llmBaseURL = baseURL
        saveAPIKeyIfNeeded()
        validationMessage = "Settings saved."
        validationSuccess = true
        dlog("Settings saved: provider=\(selectedProvider) model=\(selectedModel)", category: "Settings")
    }

    func clearAPIKey() {
        KeychainHelper.delete(account: "llm-api-key")
        apiKey = ""
        hasAPIKey = false
        validationMessage = "API key removed."
        validationSuccess = true
    }

    func validateConnection() {
        let settings = AppSettings.shared
        settings.selectedProvider = selectedProvider
        settings.selectedModel = selectedModel
        settings.llmBaseURL = baseURL
        saveAPIKeyIfNeeded()

        guard let provider = LLMProviderFactory.create() else {
            if selectedProvider == "ondevice" {
                validationMessage = LLMProviderFactory.onDeviceUnavailableReason ?? "On-device model is not available."
            } else {
                validationMessage = "Enter an API key above, then validate."
            }
            validationSuccess = false
            return
        }

        isValidating = true
        validationMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await provider.complete(
                    systemPrompt: "Respond with exactly the word: OK",
                    userMessage: "Test"
                )
                self.validationMessage = self.selectedProvider == "ondevice"
                    ? "On-device model is working."
                    : "Connected successfully."
                self.validationSuccess = true
                dlog("Validation response: \(response.prefix(100))", category: "Settings")
            } catch {
                self.validationMessage = "Connection failed: \(error.localizedDescription)"
                self.validationSuccess = false
                dlog("Validation failed: \(error)", category: "Settings")
            }
            self.isValidating = false
        }
    }

    var maskedAPIKey: String {
        guard apiKey.count > 8 else { return String(repeating: "*", count: apiKey.count) }
        let prefix = String(apiKey.prefix(4))
        let suffix = String(apiKey.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    private func saveAPIKeyIfNeeded() {
        if !apiKey.isEmpty, let data = apiKey.data(using: .utf8) {
            try? KeychainHelper.save(data, account: "llm-api-key")
            hasAPIKey = true
        }
    }
}
