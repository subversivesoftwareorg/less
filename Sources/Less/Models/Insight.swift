import Foundation
import GRDB

enum InsightType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case redundantService = "redundant_service"
    case highSpend = "high_spend"
    case newRecurring = "new_recurring"
    case priceIncrease = "price_increase"
    case unusualCategory = "unusual_category"
    case savingsOpportunity = "savings_opportunity"

    var displayName: String {
        switch self {
        case .redundantService: "Redundant Service"
        case .highSpend: "High Spend"
        case .newRecurring: "New Recurring"
        case .priceIncrease: "Price Increase"
        case .unusualCategory: "Unusual Category Spike"
        case .savingsOpportunity: "Savings Opportunity"
        }
    }

    var iconName: String {
        switch self {
        case .redundantService: "arrow.triangle.2.circlepath"
        case .highSpend: "exclamationmark.triangle"
        case .newRecurring: "repeat"
        case .priceIncrease: "arrow.up.right"
        case .unusualCategory: "chart.bar.xaxis.ascending"
        case .savingsOpportunity: "lightbulb"
        }
    }
}

enum InsightSeverity: String, Codable, DatabaseValueConvertible {
    case low
    case medium
    case high

    var weight: Int {
        switch self {
        case .high: 3
        case .medium: 2
        case .low: 1
        }
    }
}

extension InsightType {
    /// How actionable this insight type is (higher = more directly actionable).
    var actionabilityWeight: Int {
        switch self {
        case .redundantService: 5   // Cancel one of them — immediate savings
        case .priceIncrease: 4      // Negotiate or switch — clear action
        case .newRecurring: 4       // Decide to keep or cancel now, before it becomes habit
        case .highSpend: 3          // Review and potentially cut back
        case .unusualCategory: 2    // Investigate — may or may not need action
        case .savingsOpportunity: 1 // General advice — useful but less urgent
        }
    }
}

struct Insight: Identifiable, Codable, Sendable {
    var id: Int64?
    var analysisRunId: Int64
    var type: InsightType
    var title: String
    var summary: String
    var details: String
    var severity: InsightSeverity
    var relatedLineItemIds: String // JSON array of Int64
    var createdAt: Date
}

extension Insight: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "insight"

    static let analysisRun = belongsTo(AnalysisRun.self)
    static let reviewRecord = hasOne(ReviewRecord.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Combined priority score: severity * actionability. Higher = review first.
    var priorityScore: Int {
        severity.weight * type.actionabilityWeight
    }

    var lineItemIdArray: [Int64] {
        guard let data = relatedLineItemIds.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int64].self, from: data) else {
            return []
        }
        return ids
    }
}
