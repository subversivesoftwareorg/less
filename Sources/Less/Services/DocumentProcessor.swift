import CryptoKit
import Foundation

actor DocumentProcessor {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Import a PDF file: extract text, send to AI, store line items.
    func importDocument(url: URL) async throws -> Document {
        // Compute hash for deduplication
        let hash = try PDFExtractor.fileHash(url: url)
        if try database.documentExists(fileHash: hash) {
            dlog("Document already imported: \(url.lastPathComponent)", category: "DocumentProcessor")
            throw DocumentProcessorError.duplicateDocument
        }

        // Read file data for encrypted storage
        let fileData = try Data(contentsOf: url)

        // Create document record with file data stored in encrypted DB
        var doc = Document(
            filename: url.lastPathComponent,
            fileHash: hash,
            importedAt: Date(),
            rawText: "",
            processingStatus: .extractingText,
            fileData: fileData
        )
        try database.saveDocument(&doc)

        do {
            // Extract text (must happen before temp file cleanup)
            let text = try await PDFExtractor.extractText(from: url)

            // Now safe to clean up temp files
            let isTemp = url.path.hasPrefix(FileManager.default.temporaryDirectory.path)
                      || url.path.hasPrefix(NSTemporaryDirectory())
            if isTemp {
                try? FileManager.default.removeItem(at: url)
                dlog("Cleaned up temp file: \(url.lastPathComponent)", category: "DocumentProcessor")
            }
            doc.rawText = text
            try database.saveDocument(&doc)
            try database.updateDocumentStatus(doc.id!, status: .awaitingAI)

            // If no AI provider configured, stop here
            guard let provider = LLMProviderFactory.create() else {
                dlog("No LLM provider configured, text extracted but not parsed", category: "DocumentProcessor")
                try database.updateDocumentStatus(doc.id!, status: .completed)
                return doc
            }

            // Parse with AI
            try database.updateDocumentStatus(doc.id!, status: .processing)
            let parsed = try await parseWithAI(text: text, provider: provider)

            // Update document metadata
            doc.documentType = parsed.documentType
            doc.periodStart = parsed.periodStart
            doc.periodEnd = parsed.periodEnd
            doc.processingStatus = .completed
            try database.saveDocument(&doc)

            // Store line items
            let lineItems = try await resolveLineItems(parsed: parsed, documentId: doc.id!)
            try database.saveLineItems(lineItems)

            dlog("Imported \(url.lastPathComponent): \(lineItems.count) line items", category: "DocumentProcessor")
            return doc

        } catch {
            try? database.updateDocumentStatus(doc.id!, status: .failed, errorMessage: error.localizedDescription)
            throw error
        }
    }

    /// Import an inline email receipt (no PDF — text already extracted from HTML).
    func importEmailText(subject: String, text: String, date: Date, htmlData: Data?) async throws -> Document {
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        if try database.documentExists(fileHash: hash) {
            dlog("Email already imported: \(subject)", category: "DocumentProcessor")
            throw DocumentProcessorError.duplicateDocument
        }

        var doc = Document(
            filename: subject,
            fileHash: hash,
            importedAt: Date(),
            rawText: text,
            documentType: .receipt,
            processingStatus: .awaitingAI,
            fileData: htmlData
        )
        try database.saveDocument(&doc)

        do {
            guard let provider = LLMProviderFactory.create() else {
                try database.updateDocumentStatus(doc.id!, status: .completed)
                return doc
            }

            try database.updateDocumentStatus(doc.id!, status: .processing)
            let parsed = try await parseWithAI(text: text, provider: provider)

            doc.documentType = parsed.documentType ?? .receipt
            doc.periodStart = parsed.periodStart
            doc.periodEnd = parsed.periodEnd
            doc.processingStatus = .completed
            try database.saveDocument(&doc)

            let lineItems = try await resolveLineItems(parsed: parsed, documentId: doc.id!)
            try database.saveLineItems(lineItems)

            dlog("Imported email '\(subject)': \(lineItems.count) line items", category: "DocumentProcessor")
            return doc
        } catch {
            try? database.updateDocumentStatus(doc.id!, status: .failed, errorMessage: error.localizedDescription)
            throw error
        }
    }

    // MARK: - AI Parsing

    private func parseWithAI(text: String, provider: LLMProvider) async throws -> ParsedDocument {
        let systemPrompt = """
            You are a document parser for consumption tracking. Analyze the provided text extracted \
            from a PDF (receipt, credit card statement, utility bill, or bank statement) and extract \
            structured data including both financial amounts AND consumption quantities.

            Return ONLY valid JSON with this exact structure:
            {
              "documentType": "credit_card_statement" | "receipt" | "utility_bill" | "bank_statement" | "other",
              "periodStart": "YYYY-MM-DD" or null,
              "periodEnd": "YYYY-MM-DD" or null,
              "lineItems": [
                {
                  "date": "YYYY-MM-DD",
                  "vendor": "Vendor Name",
                  "description": "Brief description",
                  "amount": 15.99,
                  "suggestedCategory": "Category Name",
                  "quantity": null,
                  "unit": null
                }
              ]
            }

            SIGN CONVENTION (critical — follow exactly):
            - POSITIVE amounts = money the user SPENT or OWES (costs, charges, bills, purchases)
            - NEGATIVE amounts = money the user RECEIVED (refunds, credits, cashback, income)
            - A utility bill for $106 that the user must pay → amount: 106.0 (POSITIVE, it's a cost)
            - A refund of $50 from a store → amount: -50.0 (NEGATIVE, money coming back)
            - A solar energy credit of $30 on an electric bill → amount: -30.0 (NEGATIVE, it's a credit)
            - When in doubt, bills and charges are POSITIVE. Most line items should be positive.

            Categories (use one of these):
            Housing, Utilities, Groceries, Dining, Transportation, Entertainment, Subscriptions, \
            Healthcare, Insurance, Shopping, Travel, Education, Personal Care, Gifts, Fees & Charges, Other

            Utility bill guidelines:
            - The "Total Due", "Amount Due", or "Total Charges" is a POSITIVE cost
            - Extract the consumption quantity and unit alongside the dollar amount:
              - Electricity: quantity in kWh (unit: "kWh")
              - Natural gas: quantity in therms or CCF (unit: "therms" or "CCF")
              - Water: quantity in gallons or cubic feet (unit: "gallons" or "cuft")
            - Consumption quantities are always POSITIVE (you can't consume negative energy)
            - Set quantity and unit to null for non-utility charges

            Other guidelines:
            - Extract ALL individual charges/transactions
            - If a date is ambiguous, use the statement period date
            - Return ONLY the JSON, no other text
            """

        // Truncate very long texts to avoid token limits
        let truncatedText = String(text.prefix(50000))

        let response = try await provider.complete(
            systemPrompt: systemPrompt,
            userMessage: "Parse this financial document:\n\n\(truncatedText)"
        )

        return try parseJSON(response)
    }

    private func parseJSON(_ response: String) throws -> ParsedDocument {
        // Extract JSON from response (may be wrapped in markdown code blocks)
        var jsonString = response
        if let startRange = jsonString.range(of: "{"),
           let endRange = jsonString.range(of: "}", options: .backwards) {
            jsonString = String(jsonString[startRange.lowerBound...endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw DocumentProcessorError.parseError("Invalid response encoding")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted({
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }())

        var parsed = try decoder.decode(ParsedDocument.self, from: data)
        parsed = normalizeAmounts(parsed)
        return parsed
    }

    /// Post-process to fix common AI sign errors.
    private func normalizeAmounts(_ parsed: ParsedDocument) -> ParsedDocument {
        var items = parsed.lineItems

        // If this is a utility bill and ALL amounts are negative, the AI likely
        // got the sign wrong — bills are costs, so flip them to positive.
        if parsed.documentType == .utilityBill {
            let allNegative = items.allSatisfy { $0.amount < 0 }
            if allNegative && !items.isEmpty {
                dlog("Utility bill: all amounts negative, flipping signs", category: "DocumentProcessor")
                items = items.map { item in
                    ParsedLineItem(
                        date: item.date,
                        vendor: item.vendor,
                        description: item.description,
                        amount: abs(item.amount),
                        suggestedCategory: item.suggestedCategory,
                        quantity: item.quantity,
                        unit: item.unit
                    )
                }
            }
        }

        // Ensure consumption quantities are always positive
        items = items.map { item in
            guard let qty = item.quantity, qty < 0 else { return item }
            return ParsedLineItem(
                date: item.date,
                vendor: item.vendor,
                description: item.description,
                amount: item.amount,
                suggestedCategory: item.suggestedCategory,
                quantity: abs(qty),
                unit: item.unit
            )
        }

        return ParsedDocument(
            documentType: parsed.documentType,
            periodStart: parsed.periodStart,
            periodEnd: parsed.periodEnd,
            lineItems: items
        )
    }

    // MARK: - Line Item Resolution

    private func resolveLineItems(parsed: ParsedDocument, documentId: Int64) async throws -> [LineItem] {
        var lineItems: [LineItem] = []

        for item in parsed.lineItems {
            // Resolve or create vendor
            let vendorId = try resolveVendor(name: item.vendor)

            // Resolve category
            let categoryId = try resolveCategory(name: item.suggestedCategory)

            let lineItem = LineItem(
                documentId: documentId,
                vendorId: vendorId,
                categoryId: categoryId,
                description: item.description,
                amount: item.amount,
                date: item.date,
                rawText: "\(item.vendor): \(item.description)",
                quantity: item.quantity,
                unit: item.unit
            )
            lineItems.append(lineItem)
        }

        return lineItems
    }

    private func resolveVendor(name: String) throws -> Int64? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let existing = try database.vendor(normalizedName: normalized) {
            return existing.id
        }

        var vendor = Vendor(
            name: name,
            normalizedName: normalized,
            isSubscription: false,
            notes: ""
        )
        try database.saveVendor(&vendor)
        return vendor.id
    }

    private func resolveCategory(name: String) throws -> Int64? {
        if let existing = try database.category(named: name) {
            return existing.id
        }
        // Fall back to "Other"
        if let other = try database.category(named: "Other") {
            return other.id
        }
        return nil
    }
}

// MARK: - Parsed Document Types

struct ParsedDocument: Codable {
    let documentType: DocumentType?
    let periodStart: Date?
    let periodEnd: Date?
    let lineItems: [ParsedLineItem]
}

struct ParsedLineItem: Codable {
    let date: Date
    let vendor: String
    let description: String
    let amount: Double
    let suggestedCategory: String
    let quantity: Double?
    let unit: String?
}

enum DocumentProcessorError: LocalizedError {
    case duplicateDocument
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .duplicateDocument: "This document has already been imported."
        case .parseError(let detail): "Failed to parse AI response: \(detail)"
        }
    }
}
