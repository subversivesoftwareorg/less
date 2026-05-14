import Foundation
import GRDB

enum DocumentType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case creditCardStatement = "credit_card_statement"
    case receipt = "receipt"
    case utilityBill = "utility_bill"
    case bankStatement = "bank_statement"
    case other = "other"

    var displayName: String {
        switch self {
        case .creditCardStatement: "Credit Card Statement"
        case .receipt: "Receipt"
        case .utilityBill: "Utility Bill"
        case .bankStatement: "Bank Statement"
        case .other: "Other"
        }
    }
}

enum ProcessingStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case extractingText
    case awaitingAI
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .extractingText: "Extracting Text"
        case .awaitingAI: "Awaiting AI"
        case .processing: "Processing"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

struct Document: Identifiable, Codable, Sendable {
    var id: Int64?
    var filename: String
    var fileHash: String
    var importedAt: Date
    var rawText: String
    var documentType: DocumentType?
    var periodStart: Date?
    var periodEnd: Date?
    var processingStatus: ProcessingStatus
    var errorMessage: String?
    var fileData: Data?  // Original file stored encrypted in SQLCipher
}

extension Document: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "document"

    static let lineItems = hasMany(LineItem.self)
    var lineItems: QueryInterfaceRequest<LineItem> {
        request(for: Document.lineItems)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
