import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.appDatabase) private var database
    let document: Document
    @State private var lineItems: [LineItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.filename)
                            .font(.title2)
                            .fontWeight(.semibold)

                        HStack(spacing: 12) {
                            if let type = document.documentType {
                                Label(type.displayName, systemImage: "doc.text")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text(document.importedAt, format: .dateTime.month().day().year())
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }

                        if let start = document.periodStart, let end = document.periodEnd {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text("Period: ") +
                                Text(start, format: .dateTime.month().day()) +
                                Text(" – ") +
                                Text(end, format: .dateTime.month().day().year())
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    StatusBadge(status: document.processingStatus)
                }

                if let error = document.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Line Items
                if !lineItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Extracted Items")
                                .font(.headline)
                            Spacer()
                            Text("\(lineItems.count) items")
                                .foregroundStyle(.secondary)
                            Text("Total: \(totalAmount, format: .currency(code: "USD"))")
                                .fontWeight(.medium)
                        }

                        ForEach(lineItems) { item in
                            LineItemRow(
                                item: item,
                                onFlipSign: {
                                    guard let id = item.id else { return }
                                    try? database.flipLineItemSign(id)
                                    loadLineItems()
                                },
                                onChanged: {
                                    loadLineItems()
                                }
                            )
                        }
                    }
                } else if document.processingStatus == .completed {
                    Text("No line items extracted from this document.")
                        .foregroundStyle(.secondary)
                } else if document.processingStatus == .failed {
                    Text("Processing failed. Try re-importing this document.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing...")
                            .foregroundStyle(.secondary)
                    }
                }

                // Raw text preview
                if !document.rawText.isEmpty {
                    DisclosureGroup("Extracted Text") {
                        ScrollView {
                            Text(document.rawText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            .padding()
        }
        .task {
            loadLineItems()
        }
        .onChange(of: document.id) {
            loadLineItems()
        }
    }

    private var totalAmount: Double {
        lineItems.reduce(0) { $0 + $1.amount }
    }

    private func loadLineItems() {
        guard let docId = document.id else { return }
        lineItems = (try? database.lineItems(forDocument: docId)) ?? []
    }
}

struct LineItemRow: View {
    @Environment(\.appDatabase) private var database
    let item: LineItem
    var onFlipSign: (() -> Void)?
    var onChanged: (() -> Void)?

    @State private var isEditingDate = false
    @State private var isEditingAmount = false
    @State private var editDate: Date = .now
    @State private var editAmount: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Editable date
                    if isEditingDate {
                        DatePicker("", selection: $editDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .frame(width: 110)
                            .onSubmit { saveDate() }
                            .onExitCommand { isEditingDate = false }

                        Button("Done") { saveDate() }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    } else {
                        Text(item.date, format: .dateTime.month().day().year())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .onTapGesture {
                                editDate = item.date
                                isEditingDate = true
                            }
                            .help("Click to edit date")
                    }

                    if let qty = item.quantity, let unit = item.unit {
                        Text("\(ConsumptionType.from(unit: unit).formatWithUnit(qty, unit: unit))")
                            .font(.caption)
                            .foregroundStyle(ConsumptionType.from(unit: unit).color)
                    }
                }
            }

            Spacer()

            // Editable amount
            VStack(alignment: .trailing, spacing: 2) {
                if isEditingAmount {
                    HStack(spacing: 4) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Amount", text: $editAmount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit { saveAmount() }
                            .onExitCommand { isEditingAmount = false }

                        Button("Done") { saveAmount() }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                } else {
                    Text(item.amount, format: .currency(code: "USD"))
                        .fontWeight(.medium)
                        .foregroundStyle(item.amount < 0 ? .green : .primary)
                        .onTapGesture {
                            editAmount = String(format: "%.2f", item.amount)
                            isEditingAmount = true
                        }
                        .help("Click to edit amount")

                    Text(item.amount >= 0 ? "cost" : "credit")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button {
                editDate = item.date
                isEditingDate = true
            } label: {
                Label("Edit Date", systemImage: "calendar")
            }

            Button {
                editAmount = String(format: "%.2f", item.amount)
                isEditingAmount = true
            } label: {
                Label("Edit Amount", systemImage: "dollarsign.circle")
            }

            Divider()

            if item.documentId != nil {
                Button {
                    openSourceDocument()
                } label: {
                    Label("Open Source Document", systemImage: "doc.text")
                }
            }

            if let onFlipSign {
                Button {
                    onFlipSign()
                } label: {
                    if item.amount >= 0 {
                        Label("Mark as Credit", systemImage: "arrow.uturn.down")
                    } else {
                        Label("Mark as Cost", systemImage: "arrow.uturn.up")
                    }
                }
            }
        }
    }

    private func saveDate() {
        guard let id = item.id else { return }
        try? database.updateLineItem(id, date: editDate)
        isEditingDate = false
        onChanged?()
    }

    private func saveAmount() {
        guard let id = item.id, let newAmount = Double(editAmount) else {
            isEditingAmount = false
            return
        }
        try? database.updateLineItem(id, amount: newAmount)
        isEditingAmount = false
        onChanged?()
    }

    private func openSourceDocument() {
        guard let docId = item.documentId,
              let doc = try? database.document(id: docId),
              let fileData = doc.fileData else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(doc.filename)
        do {
            try fileData.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
        } catch {
            dlog("Failed to open document: \(error)", category: "LineItemRow")
        }
    }
}
