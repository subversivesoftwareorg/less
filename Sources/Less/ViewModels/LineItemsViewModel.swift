import Foundation
import Observation
import GRDB

@Observable final class LineItemsViewModel {
    var lineItems: [LineItem] = []
    var searchText: String = ""
    var selectedCategoryId: Int64?
    var categories: [SpendingCategory] = []

    private let database: AppDatabase
    private var observationTask: Task<Void, Never>?

    init(database: AppDatabase, categoryId: Int64? = nil) {
        self.database = database
        self.selectedCategoryId = categoryId
        self.categories = (try? database.allCategories()) ?? []
        loadItems()
    }

    func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let observation = ValueObservation.tracking { db in
                try LineItem.order(Column("date").desc).fetchAll(db)
            }
            do {
                for try await items in observation.values(in: database.dbQueue) {
                    self.lineItems = self.applyFilters(items)
                }
            } catch {
                dlog("LineItems observation error: \(error)", category: "LineItemsViewModel")
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }

    func loadItems() {
        if let categoryId = selectedCategoryId {
            lineItems = (try? database.lineItems(forCategory: categoryId)) ?? []
        } else {
            lineItems = (try? database.allLineItems()) ?? []
        }
    }

    var filteredItems: [LineItem] {
        applyFilters(lineItems)
    }

    var totalAmount: Double {
        filteredItems.reduce(0) { $0 + $1.amount }
    }

    private func applyFilters(_ items: [LineItem]) -> [LineItem] {
        var result = items

        if let categoryId = selectedCategoryId {
            result = result.filter { $0.categoryId == categoryId }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.description.lowercased().contains(query) ||
                $0.rawText.lowercased().contains(query)
            }
        }

        return result
    }
}
