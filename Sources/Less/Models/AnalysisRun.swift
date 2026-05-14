import Foundation
import GRDB

struct AnalysisRun: Identifiable, Codable, Sendable {
    var id: Int64?
    var runDate: Date
    var periodStart: Date?
    var periodEnd: Date?
    var documentCount: Int
    var insightCount: Int
    var providerUsed: String
}

extension AnalysisRun: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "analysisRun"

    static let insights = hasMany(Insight.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
