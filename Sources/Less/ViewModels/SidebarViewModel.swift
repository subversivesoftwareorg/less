import Foundation
import Observation
import GRDB

@Observable final class SidebarViewModel {
    var periods: [(year: Int, month: Int)] = []
    var categories: [SpendingCategory] = []
    var pendingInsightCount: Int = 0
    var documentCount: Int = 0

    private let database: AppDatabase
    private var observationTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        // Synchronous pre-populate
        self.periods = (try? database.availablePeriods()) ?? []
        self.categories = (try? database.allCategories()) ?? []
        self.pendingInsightCount = (try? database.pendingInsights().count) ?? 0
        self.documentCount = (try? database.documentCount()) ?? 0
    }

    func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Observe line items for period changes
            let observation = ValueObservation.tracking { db -> SidebarData in
                let periods = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT
                        CAST(strftime('%Y', date) AS INTEGER) AS year,
                        CAST(strftime('%m', date) AS INTEGER) AS month
                    FROM lineItem
                    ORDER BY year DESC, month DESC
                    """).map { (year: $0["year"] as Int, month: $0["month"] as Int) }

                let categories = try SpendingCategory.order(Column("sortOrder").asc).fetchAll(db)
                let pendingCount = try ReviewRecord.filter(Column("status") == ReviewStatus.pending.rawValue).fetchCount(db)
                let docCount = try Document.fetchCount(db)

                return SidebarData(
                    periods: periods,
                    categories: categories,
                    pendingInsightCount: pendingCount,
                    documentCount: docCount
                )
            }

            do {
                for try await data in observation.values(in: database.dbQueue) {
                    self.periods = data.periods
                    self.categories = data.categories
                    self.pendingInsightCount = data.pendingInsightCount
                    self.documentCount = data.documentCount
                }
            } catch {
                dlog("Sidebar observation error: \(error)", category: "SidebarViewModel")
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }
}

private struct SidebarData {
    let periods: [(year: Int, month: Int)]
    let categories: [SpendingCategory]
    let pendingInsightCount: Int
    let documentCount: Int
}
