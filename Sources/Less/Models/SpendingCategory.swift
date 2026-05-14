import Foundation
import GRDB

struct SpendingCategory: Identifiable, Codable, Sendable {
    var id: Int64?
    var name: String
    var colorHex: String
    var icon: String
    var isSystem: Bool
    var sortOrder: Int
}

extension SpendingCategory: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "category"

    static let lineItems = hasMany(LineItem.self, using: LineItem.categoryForeignKey)
    static let vendors = hasMany(Vendor.self, using: Vendor.defaultCategoryForeignKey)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
