import Foundation
import Observation
import GRDB

struct ConsumptionSummary {
    let type: ConsumptionType
    let unit: String
    let currentMonth: Double
    let previousMonth: Double
    let trend: [(year: Int, month: Int, total: Double)]
}

@Observable final class DashboardViewModel {
    var totalDocuments: Int = 0
    var totalLineItems: Int = 0
    var totalSpending: Double = 0
    var currentMonthSpending: Double = 0
    var categoryBreakdown: [(category: SpendingCategory, amount: Double)] = []
    var monthlyTotals: [(year: Int, month: Int, total: Double)] = []
    var consumptionSummaries: [ConsumptionSummary] = []

    private let database: AppDatabase
    private var observationTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        loadData()
    }

    func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let observation = ValueObservation.tracking { db -> Bool in
                _ = try LineItem.fetchCount(db)
                _ = try Document.fetchCount(db)
                return true
            }
            do {
                for try await _ in observation.values(in: database.dbQueue) {
                    self.loadData()
                }
            } catch {
                dlog("Dashboard observation error: \(error)", category: "DashboardViewModel")
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func loadData() {
        totalDocuments = (try? database.documentCount()) ?? 0
        totalLineItems = (try? database.lineItemCount()) ?? 0

        let now = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)

        // Previous month
        let prevMonth = month == 1 ? 12 : month - 1
        let prevYear = month == 1 ? year - 1 : year

        if let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
           let end = cal.date(byAdding: .month, value: 1, to: start) {
            currentMonthSpending = (try? database.totalSpending(year: year, month: month)) ?? 0

            categoryBreakdown = ((try? database.categoryTotals(from: start, to: end)) ?? [])
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
        }

        // Monthly spending totals
        loadMonthlyTotals()
        totalSpending = monthlyTotals.reduce(0) { $0 + $1.total }

        // Consumption summaries for each unit that has data
        loadConsumptionSummaries(year: year, month: month, prevYear: prevYear, prevMonth: prevMonth)
    }

    private func loadMonthlyTotals() {
        let periods = (try? database.availablePeriods()) ?? []
        monthlyTotals = periods.prefix(12).compactMap { period in
            let total = (try? database.totalSpending(year: period.year, month: period.month)) ?? 0
            return (year: period.year, month: period.month, total: total)
        }
    }

    private func loadConsumptionSummaries(year: Int, month: Int, prevYear: Int, prevMonth: Int) {
        let units = (try? database.availableConsumptionUnits()) ?? []
        consumptionSummaries = units.compactMap { unit in
            let type = ConsumptionType.from(unit: unit)
            guard type != .money else { return nil }

            let current = (try? database.totalConsumption(unit: unit, year: year, month: month)) ?? 0
            let previous = (try? database.totalConsumption(unit: unit, year: prevYear, month: prevMonth)) ?? 0
            let trend = (try? database.consumptionTrend(unit: unit)) ?? []

            // Only include if there's any data
            guard current > 0 || !trend.isEmpty else { return nil }

            return ConsumptionSummary(
                type: type,
                unit: unit,
                currentMonth: current,
                previousMonth: previous,
                trend: trend
            )
        }
    }
}
