import Foundation
import GRDB
import SwiftUI

// MARK: - Database

final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    static let shared: AppDatabase = {
        do {
            let url = try AppDatabase.databaseURL()
            let key = try AppDatabase.databaseKey()
            return try AppDatabase(url: url, key: key)
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    /// Open an encrypted database with a raw key stored in Keychain.
    convenience init(url: URL, key: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let hexKey = key.map { String(format: "%02x", $0) }.joined()
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA key = \"x'\(hexKey)'\"")
        }
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try self.init(queue)
        dlog("AppDatabase opened (encrypted) at: \(url.path)", category: "AppDatabase")
    }

    /// Open an unencrypted database (for testing).
    convenience init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let queue = try DatabaseQueue(path: url.path)
        try self.init(queue)
        dlog("AppDatabase opened (unencrypted) at: \(url.path)", category: "AppDatabase")
    }

    private static func databaseURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Less", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("less.sqlite")
    }

    private static func databaseKey() throws -> Data {
        let account = "database-encryption-key"
        if let existing = try? KeychainHelper.load(account: account) {
            return existing
        }
        var key = Data(count: 32)
        let result = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else {
            throw KeychainError.unhandledError(status: result)
        }
        try KeychainHelper.save(key, account: account)
        dlog("Generated new database encryption key", category: "AppDatabase")
        return key
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "category") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("colorHex", .text).notNull().defaults(to: "#007AFF")
                t.column("icon", .text).notNull().defaults(to: "folder")
                t.column("isSystem", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "vendor") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("normalizedName", .text).notNull()
                t.column("defaultCategoryId", .integer).references("category", onDelete: .setNull)
                t.column("isSubscription", .boolean).notNull().defaults(to: false)
                t.column("notes", .text).notNull().defaults(to: "")
            }

            try db.create(table: "document") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filename", .text).notNull()
                t.column("fileHash", .text).notNull().unique()
                t.column("importedAt", .datetime).notNull()
                t.column("rawText", .text).notNull().defaults(to: "")
                t.column("documentType", .text)
                t.column("periodStart", .datetime)
                t.column("periodEnd", .datetime)
                t.column("processingStatus", .text).notNull().defaults(to: "pending")
                t.column("errorMessage", .text)
            }

            try db.create(table: "lineItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("documentId", .integer).notNull().references("document", onDelete: .cascade)
                t.column("vendorId", .integer).references("vendor", onDelete: .setNull)
                t.column("categoryId", .integer).references("category", onDelete: .setNull)
                t.column("description", .text).notNull()
                t.column("amount", .double).notNull()
                t.column("date", .datetime).notNull()
                t.column("rawText", .text).notNull().defaults(to: "")
            }

            try db.create(table: "analysisRun") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("runDate", .datetime).notNull()
                t.column("periodStart", .datetime)
                t.column("periodEnd", .datetime)
                t.column("documentCount", .integer).notNull().defaults(to: 0)
                t.column("insightCount", .integer).notNull().defaults(to: 0)
                t.column("providerUsed", .text).notNull().defaults(to: "")
            }

            try db.create(table: "insight") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("analysisRunId", .integer).notNull().references("analysisRun", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("details", .text).notNull().defaults(to: "")
                t.column("severity", .text).notNull().defaults(to: "medium")
                t.column("relatedLineItemIds", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "reviewRecord") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("insightId", .integer).notNull().unique().references("insight", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("reviewedAt", .datetime)
                t.column("userNote", .text).notNull().defaults(to: "")
            }

            // Seed default categories
            let categories: [(String, String, String, Int)] = [
                ("Housing", "#8B5CF6", "house", 0),
                ("Utilities", "#F59E0B", "bolt", 1),
                ("Groceries", "#10B981", "cart", 2),
                ("Dining", "#EF4444", "fork.knife", 3),
                ("Transportation", "#3B82F6", "car", 4),
                ("Entertainment", "#EC4899", "tv", 5),
                ("Subscriptions", "#6366F1", "repeat", 6),
                ("Healthcare", "#14B8A6", "heart", 7),
                ("Insurance", "#64748B", "shield", 8),
                ("Shopping", "#F97316", "bag", 9),
                ("Travel", "#06B6D4", "airplane", 10),
                ("Education", "#8B5CF6", "book", 11),
                ("Personal Care", "#D946EF", "sparkles", 12),
                ("Gifts", "#F43F5E", "gift", 13),
                ("Fees & Charges", "#78716C", "banknote", 14),
                ("Other", "#9CA3AF", "questionmark.circle", 15),
            ]
            for (name, color, icon, order) in categories {
                try db.execute(
                    sql: "INSERT INTO category (name, colorHex, icon, isSystem, sortOrder) VALUES (?, ?, ?, 1, ?)",
                    arguments: [name, color, icon, order]
                )
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "document") { t in
                t.add(column: "fileData", .blob)
            }
        }

        migrator.registerMigration("v3") { db in
            // Recreate lineItem table with nullable documentId + new columns.
            // SQLite doesn't support ALTER COLUMN to change nullability.
            try db.rename(table: "lineItem", to: "lineItem_old")

            try db.create(table: "lineItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("documentId", .integer).references("document", onDelete: .cascade)
                t.column("vendorId", .integer).references("vendor", onDelete: .setNull)
                t.column("categoryId", .integer).references("category", onDelete: .setNull)
                t.column("description", .text).notNull()
                t.column("amount", .double).notNull()
                t.column("date", .datetime).notNull()
                t.column("rawText", .text).notNull().defaults(to: "")
                t.column("quantity", .double)
                t.column("unit", .text)
            }

            try db.execute(sql: """
                INSERT INTO lineItem (id, documentId, vendorId, categoryId, description, amount, date, rawText)
                SELECT id, documentId, vendorId, categoryId, description, amount, date, rawText
                FROM lineItem_old
                """)

            try db.drop(table: "lineItem_old")
        }

        return migrator
    }
}

// MARK: - SwiftUI Environment

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase = AppDatabase.shared
}

extension EnvironmentValues {
    var appDatabase: AppDatabase {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

// MARK: - Document Queries

extension AppDatabase {
    /// Fetch all documents without file data (for list views).
    func allDocuments() throws -> [Document] {
        try dbQueue.read { db in
            try Document
                .select(Column("id"), Column("filename"), Column("fileHash"),
                        Column("importedAt"), Column("rawText"), Column("documentType"),
                        Column("periodStart"), Column("periodEnd"),
                        Column("processingStatus"), Column("errorMessage"))
                .order(Column("importedAt").desc)
                .fetchAll(db)
        }
    }

    func document(id: Int64) throws -> Document? {
        try dbQueue.read { db in
            try Document.fetchOne(db, id: id)
        }
    }

    func documentExists(fileHash: String) throws -> Bool {
        try dbQueue.read { db in
            try Document.filter(Column("fileHash") == fileHash).fetchCount(db) > 0
        }
    }

    @discardableResult
    func saveDocument(_ document: inout Document) throws -> Document {
        try dbQueue.write { db in
            try document.save(db)
            return document
        }
    }

    func updateDocumentStatus(_ id: Int64, status: ProcessingStatus, errorMessage: String? = nil) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE document SET processingStatus = ?, errorMessage = ? WHERE id = ?",
                arguments: [status.rawValue, errorMessage, id]
            )
        }
    }

    func deleteDocument(_ id: Int64) throws {
        try dbQueue.write { db in
            _ = try Document.deleteOne(db, id: id)
        }
    }
}

// MARK: - LineItem Queries

extension AppDatabase {
    func lineItems(forDocument documentId: Int64) throws -> [LineItem] {
        try dbQueue.read { db in
            try LineItem
                .filter(Column("documentId") == documentId)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    func allLineItems() throws -> [LineItem] {
        try dbQueue.read { db in
            try LineItem.order(Column("date").desc).fetchAll(db)
        }
    }

    func lineItems(from startDate: Date, to endDate: Date) throws -> [LineItem] {
        try dbQueue.read { db in
            try LineItem
                .filter(Column("date") >= startDate && Column("date") < endDate)
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }

    func lineItems(forCategory categoryId: Int64) throws -> [LineItem] {
        try dbQueue.read { db in
            try LineItem
                .filter(Column("categoryId") == categoryId)
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }

    @discardableResult
    func saveLineItem(_ lineItem: inout LineItem) throws -> LineItem {
        try dbQueue.write { db in
            try lineItem.save(db)
            return lineItem
        }
    }

    func saveLineItems(_ lineItems: [LineItem]) throws {
        try dbQueue.write { db in
            for var item in lineItems {
                try item.save(db)
            }
        }
    }

    func deleteLineItem(_ id: Int64) throws {
        try dbQueue.write { db in
            _ = try LineItem.deleteOne(db, id: id)
        }
    }

    /// Flip the sign of a line item's amount (cost ↔ credit).
    func flipLineItemSign(_ id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE lineItem SET amount = -amount WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Update a line item's date, amount, and/or description.
    func updateLineItem(_ id: Int64, date: Date? = nil, amount: Double? = nil, description: String? = nil) throws {
        try dbQueue.write { db in
            var sets: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let date {
                sets.append("date = ?")
                args.append(date)
            }
            if let amount {
                sets.append("amount = ?")
                args.append(amount)
            }
            if let description {
                sets.append("description = ?")
                args.append(description)
            }

            guard !sets.isEmpty else { return }
            args.append(id)
            let sql = "UPDATE lineItem SET \(sets.joined(separator: ", ")) WHERE id = ?"
            try db.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }
}

// MARK: - Category Queries

extension AppDatabase {
    func allCategories() throws -> [SpendingCategory] {
        try dbQueue.read { db in
            try SpendingCategory.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    func category(id: Int64) throws -> SpendingCategory? {
        try dbQueue.read { db in
            try SpendingCategory.fetchOne(db, id: id)
        }
    }

    func category(named name: String) throws -> SpendingCategory? {
        try dbQueue.read { db in
            try SpendingCategory.filter(Column("name") == name).fetchOne(db)
        }
    }

    /// Returns categories with their total spending amounts for a date range.
    func categoryTotals(from startDate: Date, to endDate: Date) throws -> [(SpendingCategory, Double)] {
        try dbQueue.read { db in
            let categories = try SpendingCategory.order(Column("sortOrder").asc).fetchAll(db)
            return try categories.map { category in
                let total = try LineItem
                    .filter(Column("categoryId") == category.id && Column("date") >= startDate && Column("date") < endDate)
                    .select(sum(Column("amount")))
                    .asRequest(of: Double?.self)
                    .fetchOne(db) ?? 0
                return (category, total ?? 0)
            }
        }
    }
}

// MARK: - Vendor Queries

extension AppDatabase {
    func allVendors() throws -> [Vendor] {
        try dbQueue.read { db in
            try Vendor.order(Column("name").asc).fetchAll(db)
        }
    }

    func vendor(normalizedName: String) throws -> Vendor? {
        try dbQueue.read { db in
            try Vendor.filter(Column("normalizedName") == normalizedName).fetchOne(db)
        }
    }

    @discardableResult
    func saveVendor(_ vendor: inout Vendor) throws -> Vendor {
        try dbQueue.write { db in
            try vendor.save(db)
            return vendor
        }
    }
}

// MARK: - Insight Queries

extension AppDatabase {
    func allInsights() throws -> [Insight] {
        try dbQueue.read { db in
            try Insight.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func pendingInsights() throws -> [Insight] {
        try dbQueue.read { db in
            try Insight
                .joining(required: Insight.reviewRecord.filter(Column("status") == ReviewStatus.pending.rawValue))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func reviewRecord(forInsight insightId: Int64) throws -> ReviewRecord? {
        try dbQueue.read { db in
            try ReviewRecord.filter(Column("insightId") == insightId).fetchOne(db)
        }
    }

    func reviewedInsightIds() throws -> Set<Int64> {
        try dbQueue.read { db in
            let ids = try ReviewRecord
                .filter(Column("status") != ReviewStatus.pending.rawValue)
                .select(Column("insightId"))
                .asRequest(of: Int64.self)
                .fetchAll(db)
            return Set(ids)
        }
    }

    @discardableResult
    func saveInsight(_ insight: inout Insight) throws -> Insight {
        try dbQueue.write { db in
            try insight.save(db)
            // Auto-create a pending review record
            var review = ReviewRecord(
                insightId: insight.id!,
                status: .pending,
                userNote: ""
            )
            try review.save(db)
            return insight
        }
    }

    func updateReviewStatus(_ insightId: Int64, status: ReviewStatus, note: String = "") throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE reviewRecord SET status = ?, reviewedAt = ?, userNote = ? WHERE insightId = ?",
                arguments: [status.rawValue, Date(), note, insightId]
            )
        }
    }
}

// MARK: - AnalysisRun Queries

extension AppDatabase {
    @discardableResult
    func saveAnalysisRun(_ run: inout AnalysisRun) throws -> AnalysisRun {
        try dbQueue.write { db in
            try run.save(db)
            return run
        }
    }

    func latestAnalysisRun() throws -> AnalysisRun? {
        try dbQueue.read { db in
            try AnalysisRun.order(Column("runDate").desc).fetchOne(db)
        }
    }
}

// MARK: - Aggregation Queries

extension AppDatabase {
    /// Returns distinct (year, month) pairs that have line items, sorted descending.
    func availablePeriods() throws -> [(year: Int, month: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT
                    CAST(strftime('%Y', date) AS INTEGER) AS year,
                    CAST(strftime('%m', date) AS INTEGER) AS month
                FROM lineItem
                ORDER BY year DESC, month DESC
                """)
            return rows.map { (year: $0["year"], month: $0["month"]) }
        }
    }

    /// Total spending for a given month.
    func totalSpending(year: Int, month: Int) throws -> Double {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount), 0) AS total
                FROM lineItem
                WHERE CAST(strftime('%Y', date) AS INTEGER) = ?
                  AND CAST(strftime('%m', date) AS INTEGER) = ?
                """, arguments: [year, month])
            return row?["total"] ?? 0
        }
    }

    /// Number of documents currently in the database.
    func documentCount() throws -> Int {
        try dbQueue.read { db in
            try Document.fetchCount(db)
        }
    }

    /// Number of line items currently in the database.
    func lineItemCount() throws -> Int {
        try dbQueue.read { db in
            try LineItem.fetchCount(db)
        }
    }
}

// MARK: - Consumption Queries

extension AppDatabase {
    /// Total consumption for a given unit in a given month.
    func totalConsumption(unit: String, year: Int, month: Int) throws -> Double {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(quantity), 0) AS total
                FROM lineItem
                WHERE unit = ?
                  AND CAST(strftime('%Y', date) AS INTEGER) = ?
                  AND CAST(strftime('%m', date) AS INTEGER) = ?
                """, arguments: [unit, year, month])
            return row?["total"] ?? 0
        }
    }

    /// Monthly consumption trend for a unit (last 12 months with data).
    func consumptionTrend(unit: String) throws -> [(year: Int, month: Int, total: Double)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    CAST(strftime('%Y', date) AS INTEGER) AS year,
                    CAST(strftime('%m', date) AS INTEGER) AS month,
                    COALESCE(SUM(quantity), 0) AS total
                FROM lineItem
                WHERE unit = ?
                GROUP BY year, month
                ORDER BY year DESC, month DESC
                LIMIT 12
                """, arguments: [unit])
            return rows.map { (year: $0["year"], month: $0["month"], total: $0["total"]) }
        }
    }

    /// All distinct units that have data (excluding nil/empty).
    func availableConsumptionUnits() throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT unit FROM lineItem
                WHERE unit IS NOT NULL AND unit != ''
                ORDER BY unit
                """)
            return rows.compactMap { $0["unit"] as String? }
        }
    }

    /// Save a manual consumption entry (no document).
    @discardableResult
    func saveManualEntry(
        description: String,
        amount: Double,
        quantity: Double,
        unit: String,
        date: Date,
        categoryId: Int64? = nil
    ) throws -> LineItem {
        try dbQueue.write { db in
            var item = LineItem(
                documentId: nil,
                categoryId: categoryId,
                description: description,
                amount: amount,
                date: date,
                rawText: "",
                quantity: quantity,
                unit: unit
            )
            try item.save(db)
            return item
        }
    }
}
