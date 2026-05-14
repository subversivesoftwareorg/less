import Foundation
import GRDB

struct Vendor: Identifiable, Codable, Sendable {
    var id: Int64?
    var name: String
    var normalizedName: String
    var defaultCategoryId: Int64?
    var isSubscription: Bool
    var notes: String
}

extension Vendor: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "vendor"

    static let defaultCategoryForeignKey = ForeignKey(["defaultCategoryId"])
    static let defaultCategory = belongsTo(SpendingCategory.self, using: defaultCategoryForeignKey)

    static let lineItems = hasMany(LineItem.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
