import SwiftUI
import Charts

struct SpendingChartView: View {
    let monthlyTotals: [(year: Int, month: Int, total: Double)]

    var body: some View {
        Chart {
            ForEach(monthlyTotals.reversed(), id: \.month) { item in
                BarMark(
                    x: .value("Month", monthLabel(year: item.year, month: item.month)),
                    y: .value("Spending", item.total)
                )
                .foregroundStyle(.blue.gradient)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private func monthLabel(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(month)"
    }
}
