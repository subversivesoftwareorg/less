import SwiftUI

struct GmailImportView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: GmailImportViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                importContent(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 550, minHeight: 500)
        .task {
            let vm = GmailImportViewModel(database: database)
            await vm.checkAuth()
            viewModel = vm
        }
    }

    @ViewBuilder
    private func importContent(vm: GmailImportViewModel) -> some View {
        VStack(spacing: 0) {
            // Connection status
            HStack {
                if vm.isAuthorized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Gmail connected")
                        .font(.callout)
                    Spacer()
                    Button("Disconnect") {
                        Task { await vm.disconnectGmail() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .foregroundStyle(.orange)
                    Text("Not connected")
                        .font(.callout)
                    Spacer()

                    if !GmailConfig.isConfigured {
                        Text("Set up Google Cloud credentials in Settings first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Connect Gmail") {
                            Task { await vm.connectGmail() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding()

            if vm.isAuthorized {
                Divider()

                // Date range
                HStack {
                    DatePicker("From", selection: Binding(get: { vm.startDate }, set: { vm.startDate = $0 }), displayedComponents: .date)
                        .frame(maxWidth: 200)
                    DatePicker("To", selection: Binding(get: { vm.endDate }, set: { vm.endDate = $0 }), displayedComponents: .date)
                        .frame(maxWidth: 200)

                    Spacer()

                    Button {
                        Task { await vm.searchReceipts() }
                    } label: {
                        if vm.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Search Gmail", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(vm.isSearching || vm.isImporting)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Results
                if vm.messages.isEmpty && !vm.isSearching {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "envelope.open")
                    } description: {
                        Text("Set a date range and click Search to find receipts in Gmail")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Header
                    HStack {
                        Text("Found \(vm.messages.count) emails")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if vm.alreadyImportedCount > 0 {
                            Text("(\(vm.alreadyImportedCount) already imported)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button("Select All") { vm.selectAll() }
                            .buttonStyle(.plain)
                            .font(.caption)
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Button("None") { vm.deselectAll() }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    // Message list
                    List(vm.messages.indices, id: \.self) { index in
                        GmailMessageRow(message: Binding(
                            get: { vm.messages[index] },
                            set: { vm.messages[index] = $0 }
                        ))
                    }
                }

                Divider()

                // Import button + progress
                HStack {
                    if let progress = vm.importProgress {
                        ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1)))
                            .frame(maxWidth: 200)
                        Text("\(progress.current) of \(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await vm.importSelected() }
                    } label: {
                        if vm.isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Import \(vm.selectedCount) Selected")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.selectedCount == 0 || vm.isImporting)
                }
                .padding()
            }

            // Error
            if let error = vm.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { vm.errorMessage = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.05))
            }
        }
    }
}

struct GmailMessageRow: View {
    @Binding var message: GmailMessage

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $message.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(message.subject)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(message.from.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces) ?? message.from)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(message.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Type indicator
                    switch message.importType {
                    case .pdfAttachment:
                        let name = message.attachments.first?.filename ?? "PDF"
                        Label(name, systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    case .inlineReceipt:
                        Label("inline receipt", systemImage: "envelope")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
