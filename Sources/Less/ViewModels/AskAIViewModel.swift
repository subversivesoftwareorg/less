import Foundation
import Observation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()

    enum Role {
        case user
        case assistant
    }
}

@Observable final class AskAIViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false
    var errorMessage: String?

    private let database: AppDatabase
    private var cachedDataContext: String?

    init(database: AppDatabase) {
        self.database = database
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isLoading = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let provider = LLMProviderFactory.create() else {
                    throw AskAIError.noProvider
                }

                let dataContext = self.getDataContext()
                let systemPrompt = self.buildSystemPrompt(dataContext: dataContext)
                let userMessage = self.buildUserMessage(currentQuestion: text)

                let response = try await provider.complete(
                    systemPrompt: systemPrompt,
                    userMessage: userMessage
                )
                self.messages.append(ChatMessage(role: .assistant, content: response))
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func clearConversation() {
        messages.removeAll()
        cachedDataContext = nil
        errorMessage = nil
    }

    private func getDataContext() -> String {
        if let cached = cachedDataContext { return cached }
        let context = buildDataContext()
        cachedDataContext = context
        return context
    }

    // MARK: - Prompt Construction

    private func buildSystemPrompt(dataContext: String) -> String {
        """
        You are a helpful financial assistant embedded in "Less is More," a personal consumption \
        tracking app. You have access to the user's complete spending data, imported document \
        contents, and consumption metrics (electricity, gas, water, waste).

        Answer questions about the data clearly and concisely. Reference specific numbers, vendors, \
        categories, and dates. If the data doesn't contain enough information to answer, say so.

        Respond in plain, conversational English. Use markdown for readability when helpful \
        (bold, bullet points, etc.). Do NOT return JSON.

        USER DATA:

        \(dataContext)
        """
    }

    private func buildUserMessage(currentQuestion: String) -> String {
        let prior = messages.dropLast()
        if prior.isEmpty {
            return currentQuestion
        }

        var transcript = "Previous conversation:\n"
        for msg in prior {
            let label = msg.role == .user ? "User" : "Assistant"
            transcript += "\(label): \(msg.content)\n\n"
        }
        transcript += "Current question: \(currentQuestion)"
        return transcript
    }

    // MARK: - Data Context

    private func buildDataContext() -> String {
        let lineItems = (try? database.allLineItems()) ?? []
        let categories = (try? database.allCategories()) ?? []
        let vendors = (try? database.allVendors()) ?? []
        let documents = (try? database.allDocuments()) ?? []

        if lineItems.isEmpty && documents.isEmpty {
            return "No data has been imported yet."
        }

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c in
            c.id.map { ($0, c.name) }
        })
        let vendorMap = Dictionary(uniqueKeysWithValues: vendors.compactMap { v in
            v.id.map { ($0, v) }
        })

        let cal = Calendar.current
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        var context = ""

        // Overview
        let totalSpending = lineItems.reduce(0) { $0 + $1.amount }
        context += "# Overview\n"
        context += "- \(lineItems.count) transactions totaling $\(String(format: "%.2f", totalSpending))\n"
        context += "- \(documents.count) documents imported\n"
        if let earliest = lineItems.map(\.date).min(),
           let latest = lineItems.map(\.date).max() {
            context += "- Date range: \(dateFmt.string(from: earliest)) to \(dateFmt.string(from: latest))\n"
        }

        // Monthly totals
        var monthlyGroups: [String: [LineItem]] = [:]
        for item in lineItems {
            let key = String(format: "%04d-%02d",
                             cal.component(.year, from: item.date),
                             cal.component(.month, from: item.date))
            monthlyGroups[key, default: []].append(item)
        }

        context += "\n# Monthly Totals\n"
        for key in monthlyGroups.keys.sorted().reversed() {
            let items = monthlyGroups[key]!
            let total = items.reduce(0) { $0 + $1.amount }
            context += "- \(key): $\(String(format: "%.2f", total)) (\(items.count) transactions)\n"
        }

        // Category breakdown
        context += "\n# Category Breakdown\n"
        let byCat = Dictionary(grouping: lineItems) { $0.categoryId }
        var categoryTotals: [(String, Double, Int)] = []
        for (catId, items) in byCat {
            let name = catId.flatMap { categoryMap[$0] } ?? "Uncategorized"
            let total = items.reduce(0) { $0 + $1.amount }
            categoryTotals.append((name, total, items.count))
        }
        for (name, total, count) in categoryTotals.sorted(by: { $0.1 > $1.1 }) {
            context += "- \(name): $\(String(format: "%.2f", total)) (\(count) transactions)\n"
        }

        // Vendors
        context += "\n# Vendors\n"
        let byVendor = Dictionary(grouping: lineItems) { $0.vendorId }
        var vendorStats: [(String, Double, Int, Bool)] = []
        for (vendorId, items) in byVendor {
            let vendor = vendorId.flatMap { vendorMap[$0] }
            let name = vendor?.name ?? "Unknown"
            let total = items.reduce(0) { $0 + $1.amount }
            vendorStats.append((name, total, items.count, vendor?.isSubscription ?? false))
        }
        for (name, total, count, isSub) in vendorStats.sorted(by: { $0.1 > $1.1 }).prefix(30) {
            let sub = isSub ? " [SUBSCRIPTION]" : ""
            context += "- \(name): $\(String(format: "%.2f", total)) (\(count)x)\(sub)\n"
        }

        // All transactions
        context += "\n# Transactions\n"
        for item in lineItems.prefix(500) {
            let vendor = item.vendorId.flatMap { vendorMap[$0] }?.name ?? "Unknown"
            let category = item.categoryId.flatMap { categoryMap[$0] } ?? ""
            var line = "\(dateFmt.string(from: item.date)) | \(vendor) | \(item.description) | $\(String(format: "%.2f", item.amount))"
            if !category.isEmpty { line += " | \(category)" }
            if let qty = item.quantity, let unit = item.unit {
                line += " | \(String(format: "%.1f", qty)) \(unit)"
            }
            context += "- \(line)\n"
        }
        if lineItems.count > 500 {
            context += "- ... and \(lineItems.count - 500) more\n"
        }

        // Consumption
        let consumptionItems = lineItems.filter { $0.unit != nil && $0.quantity != nil }
        if !consumptionItems.isEmpty {
            context += "\n# Consumption\n"
            let byUnit = Dictionary(grouping: consumptionItems) { $0.unit ?? "" }
            for (unit, items) in byUnit.sorted(by: { $0.key < $1.key }) {
                let type = ConsumptionType.from(unit: unit)
                let total = items.compactMap(\.quantity).reduce(0, +)
                context += "## \(type.displayName) (\(unit))\n"
                let byMonth = Dictionary(grouping: items) { item -> String in
                    String(format: "%04d-%02d",
                           cal.component(.year, from: item.date),
                           cal.component(.month, from: item.date))
                }
                for key in byMonth.keys.sorted().reversed() {
                    let monthTotal = byMonth[key]!.compactMap(\.quantity).reduce(0, +)
                    context += "- \(key): \(type.formatWithUnit(monthTotal, unit: unit))\n"
                }
                context += "- Total: \(type.formatWithUnit(total, unit: unit))\n\n"
            }
        }

        // Document contents
        context += "\n# Documents\n"
        let docFmt = DateFormatter()
        docFmt.dateStyle = .medium
        for doc in documents {
            context += "## \(doc.filename)"
            if let type = doc.documentType { context += " (\(type))" }
            context += "\n"
            if let start = doc.periodStart, let end = doc.periodEnd {
                context += "Period: \(docFmt.string(from: start)) to \(docFmt.string(from: end))\n"
            }
            if !doc.rawText.isEmpty {
                context += String(doc.rawText.prefix(2000))
                if doc.rawText.count > 2000 { context += "\n[truncated]" }
                context += "\n"
            }
            context += "\n"
        }

        // Previous insights
        if let insights = try? database.allInsights(), !insights.isEmpty {
            context += "\n# Previous Insights\n"
            for insight in insights.prefix(20) {
                context += "- [\(insight.severity.rawValue)] \(insight.title): \(insight.summary)\n"
            }
        }

        return context
    }
}

enum AskAIError: LocalizedError {
    case noProvider

    var errorDescription: String? {
        switch self {
        case .noProvider: "No AI provider configured. Set your API key in Settings."
        }
    }
}
