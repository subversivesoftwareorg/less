import Foundation
import GRDB

struct LineItem: Identifiable, Codable, Sendable {
    var id: Int64?
    var documentId: Int64?      // nil for manual entries
    var vendorId: Int64?
    var categoryId: Int64?
    var description: String
    var amount: Double
    var date: Date
    var rawText: String
    var quantity: Double?       // consumption quantity (e.g., 450 kWh)
    var unit: String?           // unit of measure (e.g., "kWh", "gallons")

    /// The consumption type derived from the unit field.
    var consumptionType: ConsumptionType {
        guard let unit else { return .money }
        return ConsumptionType.from(unit: unit)
    }

    /// Whether this is a manual entry (not from a document).
    var isManualEntry: Bool {
        documentId == nil
    }
}

extension LineItem: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "lineItem"

    static let document = belongsTo(Document.self)
    static let categoryForeignKey = ForeignKey(["categoryId"])
    static let category = belongsTo(SpendingCategory.self, using: categoryForeignKey)
    static let vendor = belongsTo(Vendor.self)

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
