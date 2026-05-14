import SwiftUI

struct DocumentListView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: DocumentsViewModel?
    @State private var selectedDocument: Document?
    @State private var showingFilePicker = false

    var body: some View {
        VSplitView {
            // Document list (top)
            VStack(spacing: 0) {
                DropZoneView { urls in
                    viewModel?.importPDFs(urls: urls)
                }
                .padding()

                Divider()

                if let viewModel, !viewModel.documents.isEmpty {
                    List(viewModel.documents, selection: $selectedDocument) { doc in
                        DocumentRow(document: doc)
                            .tag(doc)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteDocument(doc)
                                    if selectedDocument?.id == doc.id {
                                        selectedDocument = nil
                                    }
                                }
                            }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.text")
                    } description: {
                        Text("Drop PDF files above or use File > Import Documents")
                    }
                    .frame(maxHeight: .infinity)
                }

                if let error = viewModel?.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Dismiss") {
                            viewModel?.errorMessage = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.05))
                }
            }
            .frame(minHeight: 200)

            // Detail pane (bottom)
            if let doc = selectedDocument {
                DocumentDetailView(document: doc)
                    .frame(minHeight: 200)
            } else {
                Text("Select a document to view details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }

            if viewModel?.isImporting == true {
                ToolbarItem {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel?.importPDFs(urls: urls)
            }
        }
        .task {
            let vm = DocumentsViewModel(database: database)
            vm.startObservation()
            viewModel = vm
        }
        .onDisappear {
            viewModel?.stopObservation()
        }
    }
}

struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.filename)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let type = document.documentType {
                        Text(type.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(document.importedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            StatusBadge(status: document.processingStatus)
        }
        .padding(.vertical, 2)
    }
}

extension Document: Hashable {
    static func == (lhs: Document, rhs: Document) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
