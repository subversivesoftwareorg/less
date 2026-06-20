import Foundation
import Observation

@Observable final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Debugging
    var debugLoggingEnabled: Bool {
        didSet { UserDefaults.standard.set(debugLoggingEnabled, forKey: "debugLoggingEnabled") }
    }

    // MARK: - LLM Provider
    var selectedProvider: String {
        didSet { UserDefaults.standard.set(selectedProvider, forKey: "selectedProvider") }
    }
    var llmBaseURL: String {
        didSet { UserDefaults.standard.set(llmBaseURL, forKey: "llmBaseURL") }
    }
    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    private init() {
        debugLoggingEnabled = UserDefaults.standard.bool(forKey: "debugLoggingEnabled")
        selectedProvider = UserDefaults.standard.string(forKey: "selectedProvider") ?? "ondevice"
        llmBaseURL = UserDefaults.standard.string(forKey: "llmBaseURL") ?? ""
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-sonnet-4-6"
    }
}
