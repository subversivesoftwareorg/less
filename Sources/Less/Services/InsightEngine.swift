import Foundation

actor InsightEngine {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Run a full analysis across all spending data, generating insights.
    /// Respects previously-reviewed insights to avoid re-surfacing them.
    func runAnalysis() async throws -> AnalysisRun {
        guard let provider = LLMProviderFactory.create() else {
            throw InsightEngineError.noProvider
        }

        dlog("Starting insight analysis", category: "InsightEngine")

        // Gather spending data
        let lineItems = try database.allLineItems()
        guard !lineItems.isEmpty else {
            throw InsightEngineError.noData
        }

        let categories = try database.allCategories()
        let vendors = try database.allVendors()
        let reviewedIds = try database.reviewedInsightIds()

        // Build summary for the AI
        let summary = buildSpendingSummary(
            lineItems: lineItems,
            categories: categories,
            vendors: vendors,
            reviewedInsightIds: reviewedIds
        )

        // Ask AI for insights
        let response = try await provider.complete(
            systemPrompt: insightSystemPrompt,
            userMessage: summary
        )

        // Parse insights from response
        let parsedInsights = try parseInsights(response)

        // Create analysis run
        var run = AnalysisRun(
            runDate: Date(),
            periodStart: lineItems.map(\.date).min(),
            periodEnd: lineItems.map(\.date).max(),
            documentCount: (try? database.documentCount()) ?? 0,
            insightCount: parsedInsights.count,
            providerUsed: provider.name
        )
        try database.saveAnalysisRun(&run)

        // Save insights
        for parsed in parsedInsights {
            var insight = Insight(
                analysisRunId: run.id!,
                type: parsed.type,
                title: parsed.title,
                summary: parsed.summary,
                details: parsed.details,
                severity: parsed.severity,
                relatedLineItemIds: "[]",
                createdAt: Date()
            )
            try database.saveInsight(&insight)
        }

        dlog("Analysis complete: \(parsedInsights.count) insights generated", category: "InsightEngine")
        return run
    }

    // MARK: - Summary Building

    private func buildSpendingSummary(
        lineItems: [LineItem],
        categories: [SpendingCategory],
        vendors: [Vendor],
        reviewedInsightIds: Set<Int64>
    ) -> String {
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c in
            c.id.map { ($0, c.name) }
        })
        let vendorMap = Dictionary(uniqueKeysWithValues: vendors.compactMap { v in
            v.id.map { ($0, v) }
        })

        // Group by month
        let cal = Calendar.current
        var monthlyGroups: [String: [LineItem]] = [:]
        for item in lineItems {
            let year = cal.component(.year, from: item.date)
            let month = cal.component(.month, from: item.date)
            let key = String(format: "%04d-%02d", year, month)
            monthlyGroups[key, default: []].append(item)
        }

        var summary = "# Spending Data Summary\n\n"

        // Monthly totals
        summary += "## Monthly Totals\n"
        for key in monthlyGroups.keys.sorted().reversed() {
            let items = monthlyGroups[key]!
            let total = items.reduce(0) { $0 + $1.amount }
            summary += "- \(key): $\(String(format: "%.2f", total)) (\(items.count) transactions)\n"
        }

        // Category breakdown
        summary += "\n## Category Breakdown (all time)\n"
        var categoryTotals: [(String, Double, Int)] = []
        let byCat = Dictionary(grouping: lineItems) { $0.categoryId }
        for (catId, items) in byCat {
            let name = catId.flatMap { categoryMap[$0] } ?? "Uncategorized"
            let total = items.reduce(0) { $0 + $1.amount }
            categoryTotals.append((name, total, items.count))
        }
        for (name, total, count) in categoryTotals.sorted(by: { $0.1 > $1.1 }) {
            summary += "- \(name): $\(String(format: "%.2f", total)) (\(count) transactions)\n"
        }

        // Vendor frequency (top 20)
        summary += "\n## Top Vendors (by frequency)\n"
        let byVendor = Dictionary(grouping: lineItems) { $0.vendorId }
        var vendorStats: [(String, Double, Int, Bool)] = []
        for (vendorId, items) in byVendor {
            let vendor = vendorId.flatMap { vendorMap[$0] }
            let name = vendor?.name ?? "Unknown"
            let total = items.reduce(0) { $0 + $1.amount }
            let isSub = vendor?.isSubscription ?? false
            vendorStats.append((name, total, items.count, isSub))
        }
        for (name, total, count, isSub) in vendorStats.sorted(by: { $0.2 > $1.2 }).prefix(20) {
            let subMarker = isSub ? " [SUBSCRIPTION]" : ""
            summary += "- \(name): $\(String(format: "%.2f", total)) (\(count)x)\(subMarker)\n"
        }

        // Consumption data (energy, water, gas, waste)
        let consumptionItems = lineItems.filter { $0.unit != nil && $0.quantity != nil }
        if !consumptionItems.isEmpty {
            summary += "\n## Consumption Data\n"
            let byUnit = Dictionary(grouping: consumptionItems) { $0.unit ?? "" }
            for (unit, items) in byUnit.sorted(by: { $0.key < $1.key }) {
                let type = ConsumptionType.from(unit: unit)
                let total = items.compactMap(\.quantity).reduce(0, +)
                summary += "### \(type.displayName) (\(unit))\n"

                // Monthly breakdown
                let byMonth = Dictionary(grouping: items) { item -> String in
                    let y = cal.component(.year, from: item.date)
                    let m = cal.component(.month, from: item.date)
                    return String(format: "%04d-%02d", y, m)
                }
                for key in byMonth.keys.sorted().reversed() {
                    let monthItems = byMonth[key]!
                    let monthTotal = monthItems.compactMap(\.quantity).reduce(0, +)
                    summary += "- \(key): \(type.formatWithUnit(monthTotal, unit: unit))\n"
                }
                summary += "- All-time total: \(type.formatWithUnit(total, unit: unit))\n\n"
            }
        }

        // Note about reviewed insights
        if !reviewedInsightIds.isEmpty {
            summary += "\n## Previously Reviewed\n"
            summary += "The user has already reviewed \(reviewedInsightIds.count) insights. "
            summary += "Do NOT regenerate insights about the same topics they've already seen.\n"
        }

        return summary
    }

    // MARK: - AI Prompt

    private var insightSystemPrompt: String {
        """
        You are a consumption analyst. Analyze the spending AND resource consumption data \
        (electricity, gas, water, waste) and identify actionable insights.

        Return ONLY valid JSON with this exact structure:
        {
          "insights": [
            {
              "type": "redundant_service|high_spend|new_recurring|price_increase|unusual_category|savings_opportunity",
              "title": "Brief title",
              "summary": "One sentence summary",
              "details": "Detailed explanation with specific numbers",
              "severity": "low|medium|high"
            }
          ]
        }

        Focus on:
        1. Redundant or overlapping subscriptions/services
        2. Unusually high charges compared to the vendor's history
        3. New recurring charges that appeared recently
        4. Price increases from the same vendor over time
        5. Spending spikes in specific categories
        6. General opportunities to save money
        7. Energy/water/gas consumption trends (spikes, seasonal patterns)
        8. Unusually high utility usage compared to prior months

        Guidelines:
        - Be specific — reference actual vendor names, dollar amounts, and consumption quantities
        - Only flag genuinely interesting patterns, not every transaction
        - If the user has already reviewed similar insights, focus on NEW patterns
        - Aim for 3-8 high-quality insights, not a long list of trivial ones
        - Return ONLY the JSON, no other text
        """
    }

    // MARK: - Parsing

    private func parseInsights(_ response: String) throws -> [ParsedInsight] {
        var jsonString = response
        if let startRange = jsonString.range(of: "{"),
           let endRange = jsonString.range(of: "}", options: .backwards) {
            jsonString = String(jsonString[startRange.lowerBound...endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw InsightEngineError.parseError
        }

        // Parse loosely — extract what we can, skip malformed entries
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let insightsArray = json["insights"] as? [[String: Any]] else {
            dlog("Insight response is not valid JSON or missing 'insights' key. Response: \(jsonString.prefix(500))", category: "InsightEngine")
            throw InsightEngineError.parseError
        }

        var results: [ParsedInsight] = []
        for entry in insightsArray {
            guard let title = entry["title"] as? String,
                  let summary = entry["summary"] as? String else {
                dlog("Skipping insight entry missing title/summary: \(entry)", category: "InsightEngine")
                continue
            }

            let typeString = entry["type"] as? String ?? ""
            let type = InsightType(fuzzyMatch: typeString)
            let severityString = entry["severity"] as? String ?? "medium"
            let severity = InsightSeverity(rawValue: severityString.lowercased()) ?? .medium
            let details = entry["details"] as? String ?? ""

            results.append(ParsedInsight(type: type, title: title, summary: summary, details: details, severity: severity))
        }

        if results.isEmpty && !insightsArray.isEmpty {
            dlog("All \(insightsArray.count) insight entries failed to parse", category: "InsightEngine")
            throw InsightEngineError.parseError
        }

        return results
    }
}

// MARK: - Types

struct ParsedInsight {
    let type: InsightType
    let title: String
    let summary: String
    let details: String
    let severity: InsightSeverity
}

extension InsightType {
    /// Fuzzy-match an AI-returned type string to an InsightType case.
    init(fuzzyMatch raw: String) {
        let s = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        if let exact = InsightType(rawValue: s) {
            self = exact
            return
        }
        // Fuzzy matching for common AI variations
        if s.contains("redundant") || s.contains("duplicate") || s.contains("overlapping") {
            self = .redundantService
        } else if s.contains("high") && (s.contains("spend") || s.contains("charge") || s.contains("cost")) {
            self = .highSpend
        } else if s.contains("recurring") || s.contains("subscription") || s.contains("new_sub") {
            self = .newRecurring
        } else if s.contains("price") && s.contains("increase") {
            self = .priceIncrease
        } else if s.contains("unusual") || s.contains("spike") || s.contains("anomal") {
            self = .unusualCategory
        } else if s.contains("saving") || s.contains("opportunity") || s.contains("reduce") || s.contains("tip") {
            self = .savingsOpportunity
        } else {
            self = .savingsOpportunity // safe fallback
        }
    }
}

enum InsightEngineError: LocalizedError {
    case noProvider
    case noData
    case parseError

    var errorDescription: String? {
        switch self {
        case .noProvider: "No AI provider configured. Set your API key in Settings."
        case .noData: "No spending data to analyze. Import some documents first."
        case .parseError: "Failed to parse AI analysis response."
        }
    }
}
