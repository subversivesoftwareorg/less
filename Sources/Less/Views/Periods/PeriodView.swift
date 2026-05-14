import SwiftUI

struct PeriodView: View {
    @Environment(\.appDatabase) private var database
    let year: Int
    let month: Int
    @State private var lineItems: [LineItem] = []
    @State private var consumptionSummaries: [(type: ConsumptionType, unit: String, total: Double)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text(periodTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(spendingTotal.formatted(.currency(code: "USD")))
                        .font(.title3)
                        .fontWeight(.bold)
                }

                // Stats
                HStack(spacing: 24) {
                    Label("\(lineItems.count) transactions", systemImage: "list.bullet.rectangle")
                    if lineItems.contains(where: { $0.isManualEntry }) {
                        Label("\(lineItems.filter(\.isManualEntry).count) manual", systemImage: "pencil")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                // Consumption summaries for this month
                if !consumptionSummaries.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(consumptionSummaries, id: \.unit) { summary in
                            HStack(spacing: 6) {
                                Image(systemName: summary.type.icon)
                                    .foregroundStyle(summary.type.color)
                                Text(summary.type.formatWithUnit(summary.total, unit: summary.unit))
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(summary.type.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Divider()

                // Transactions list
                if !lineItems.isEmpty {
                    Text("Transactions")
                        .font(.headline)

                    ForEach(lineItems) { item in
                        LineItemRow(item: item)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Data", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("No spending or consumption data for this period")
                    }
                }
            }
            .padding()
        }
        .task {
            loadData()
        }
    }

    private var spendingTotal: Double {
        lineItems.reduce(0) { $0 + $1.amount }
    }

    private var periodTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(month)/\(year)"
    }

    private func loadData() {
        let cal = Calendar.current
        if let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
           let end = cal.date(byAdding: .month, value: 1, to: start) {
            lineItems = (try? database.lineItems(from: start, to: end)) ?? []
        }

        // Load consumption totals for this month
        let units = (try? database.availableConsumptionUnits()) ?? []
        consumptionSummaries = units.compactMap { unit in
            let type = ConsumptionType.from(unit: unit)
            guard type != .money else { return nil }
            let total = (try? database.totalConsumption(unit: unit, year: year, month: month)) ?? 0
            guard total > 0 else { return nil }
            return (type: type, unit: unit, total: total)
        }
    }
}
