import Charts
import SwiftUI

struct ConsumptionSectionView: View {
    let type: ConsumptionType
    let currentMonth: Double
    let previousMonth: Double
    let trend: [(year: Int, month: Int, total: Double)]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: type.icon)
                    .foregroundStyle(type.color)

                Text(type.displayName)
                    .font(.headline)

                Spacer()

                Text(type.formatWithUnit(currentMonth, unit: unit))
                    .font(.title3)
                    .fontWeight(.bold)

                if previousMonth > 0 {
                    let pctChange = ((currentMonth - previousMonth) / previousMonth) * 100
                    HStack(spacing: 2) {
                        Image(systemName: pctChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(abs(Int(pctChange)))%")
                    }
                    .font(.caption)
                    .foregroundStyle(pctChange >= 0 ? .red : .green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (pctChange >= 0 ? Color.red : Color.green).opacity(0.1),
                        in: Capsule()
                    )
                }
            }

            // Trend chart
            if trend.count > 1 {
                Chart {
                    ForEach(trend.reversed(), id: \.month) { item in
                        LineMark(
                            x: .value("Month", monthLabel(year: item.year, month: item.month)),
                            y: .value(type.displayName, item.total)
                        )
                        .foregroundStyle(type.color)

                        AreaMark(
                            x: .value("Month", monthLabel(year: item.year, month: item.month)),
                            y: .value(type.displayName, item.total)
                        )
                        .foregroundStyle(type.color.opacity(0.1))
                    }
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(type.color.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(type.color.opacity(0.1), lineWidth: 1)
        )
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
