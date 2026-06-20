import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var isCloudProvider: Bool {
        viewModel.selectedProvider == "anthropic" || viewModel.selectedProvider == "openai-compatible"
    }

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $viewModel.selectedProvider) {
                    Text("Apple On-Device").tag("ondevice")
                    Text("Anthropic (Claude)").tag("anthropic")
                    Text("OpenAI-Compatible").tag("openai-compatible")
                }

                if viewModel.selectedProvider == "anthropic" {
                    Picker("Model", selection: $viewModel.selectedModel) {
                        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Claude Opus 4.6").tag("claude-opus-4-6")
                        Text("Claude Opus 4.7").tag("claude-opus-4-7")
                    }
                }

                if viewModel.selectedProvider == "ondevice" {
                    onDeviceStatusView
                }

                if viewModel.selectedProvider == "openai-compatible" {
                    TextField("Base URL", text: $viewModel.baseURL, prompt: Text("https://api.openai.com"))
                        .textFieldStyle(.roundedBorder)

                    Text("Works with OpenAI, Ollama, or any OpenAI-compatible API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isCloudProvider {
                Section("API Key") {
                    if viewModel.hasAPIKey {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.green)
                            Text(viewModel.maskedAPIKey)
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Change") {
                                viewModel.hasAPIKey = false
                                viewModel.apiKey = ""
                            }
                            Button("Remove", role: .destructive) {
                                viewModel.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("Paste your API key here", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Section {
                HStack {
                    Button("Save & Validate") {
                        viewModel.validateConnection()
                    }
                    .disabled(viewModel.isValidating || (isCloudProvider && !viewModel.hasAPIKey && viewModel.apiKey.isEmpty))
                    .buttonStyle(.borderedProminent)

                    if viewModel.isValidating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }

                if let message = viewModel.validationMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: viewModel.validationSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .padding(.top, 2)
                        Text(message)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                    .foregroundStyle(viewModel.validationSuccess ? .green : .red)
                }
            }

            Section("Debug") {
                Toggle("Debug Logging", isOn: Binding(
                    get: { AppSettings.shared.debugLoggingEnabled },
                    set: { AppSettings.shared.debugLoggingEnabled = $0 }
                ))
            }

            Section("Data") {
                Button("Reset Onboarding") {
                    hasCompletedOnboarding = false
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 400)
    }

    @ViewBuilder
    private var onDeviceStatusView: some View {
        if LLMProviderFactory.onDeviceAvailable {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Apple Intelligence is available on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("No API key needed. All processing happens on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("For large or complex documents, consider using a cloud provider for higher accuracy.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else if let reason = LLMProviderFactory.onDeviceUnavailableReason {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
