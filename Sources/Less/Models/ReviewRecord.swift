import Foundation
import GRDB

enum ReviewStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case reviewed
    case dismissed
    case acted

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .reviewed: "Reviewed"
        case .dismissed: "Dismissed"
        case .acted: "Acted On"
        }
    }
}

struct ReviewRecord: Identifiable, Codable, Sendable {
    var id: Int64?
    var insightId: Int64
    var status: ReviewStatus
    var reviewedAt: Date?
    var userNote: String
}

extension ReviewRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "reviewRecord"

    static let insight = belongsTo(Insight.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
