import SwiftUI

struct AskAIView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: AskAIViewModel?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if viewModel.messages.isEmpty && !viewModel.isLoading {
                                emptyState
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Thinking...")
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                }
                                .padding(.horizontal)
                                .id("loading")
                            }

                            if let error = viewModel.errorMessage {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text(error)
                                }
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.isLoading) { _, loading in
                        if loading { scrollToBottom(proxy: proxy) }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Ask about your data...", text: Binding(
                        get: { viewModel.inputText },
                        set: { viewModel.inputText = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { viewModel.sendMessage() }

                    Button { viewModel.sendMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Color(red: 0.08, green: 0.45, blue: 0.40) : .secondary)
                    .disabled(!canSend)
                }
                .padding(12)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .navigationTitle("Ask AI")
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel?.clearConversation()
                } label: {
                    Label("New Conversation", systemImage: "trash")
                }
                .disabled(viewModel?.messages.isEmpty ?? true)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AskAIViewModel(database: database)
                isInputFocused = true
            }
        }
    }

    private var canSend: Bool {
        guard let viewModel else { return false }
        return !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isLoading
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)

            Text("Ask anything about your data")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let viewModel {
                VStack(alignment: .leading, spacing: 8) {
                    SuggestedQuestion("What did I spend the most on last month?", viewModel: viewModel)
                    SuggestedQuestion("Which subscriptions do I have?", viewModel: viewModel)
                    SuggestedQuestion("How has my electricity usage changed?", viewModel: viewModel)
                    SuggestedQuestion("Summarize my spending patterns", viewModel: viewModel)
                }
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if let last = viewModel?.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            } else if viewModel?.isLoading == true {
                proxy.scrollTo("loading", anchor: .bottom)
            }
        }
    }
}

// MARK: - Suggested Question Button

private struct SuggestedQuestion: View {
    let text: String
    let viewModel: AskAIViewModel

    init(_ text: String, viewModel: AskAIViewModel) {
        self.text = text
        self.viewModel = viewModel
    }

    var body: some View {
        Button {
            viewModel.inputText = text
            viewModel.sendMessage()
        } label: {
            HStack {
                Image(systemName: "sparkle")
                    .font(.caption)
                Text(text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            messageContent

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .user {
            Text(message.content)
                .padding(10)
                .background(Color(red: 0.08, green: 0.45, blue: 0.40).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)
        } else {
            let rendered = (try? AttributedString(
                markdown: message.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(message.content)

            Text(rendered)
                .textSelection(.enabled)
        }
    }
}
