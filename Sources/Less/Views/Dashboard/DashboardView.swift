import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(\.appDatabase) private var database
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: DashboardViewModel?
    @State private var documentsViewModel: DocumentsViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Drop zone
                DropZoneView { urls in
                    documentsViewModel?.importPDFs(urls: urls)
                }
                .padding(.horizontal)

                // Action buttons row
                HStack(spacing: 12) {
                    ActionButton(icon: "camera.fill", label: "Capture Receipt") {
                        openWindow(id: "receipt-capture")
                    }
                    ActionButton(icon: "plus.circle.fill", label: "Log Consumption") {
                        openWindow(id: "manual-entry")
                    }
                    ActionButton(icon: "envelope.fill", label: "Gmail Import") {
                        openWindow(id: "gmail-import")
                    }
                }
                .padding(.horizontal)

                // Import status
                if let docsVm = documentsViewModel {
                    if docsVm.isImporting {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing documents...")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if let error = docsVm.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Dismiss") { docsVm.errorMessage = nil }
                                .buttonStyle(.plain)
                                .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    }
                }

                // Summary cards
                if let vm = viewModel {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 16) {
                        SummaryCard(
                            title: "Documents",
                            value: "\(vm.totalDocuments)",
                            icon: "doc.text",
                            color: .blue
                        )
                        SummaryCard(
                            title: "Line Items",
                            value: "\(vm.totalLineItems)",
                            icon: "list.bullet.rectangle",
                            color: .green
                        )
                        SummaryCard(
                            title: "This Month",
                            value: vm.currentMonthSpending.formatted(.currency(code: "USD")),
                            icon: "calendar",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)

                    // Monthly trend chart
                    if !vm.monthlyTotals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Monthly Spending")
                                .font(.headline)

                            SpendingChartView(monthlyTotals: vm.monthlyTotals)
                                .frame(height: 200)
                        }
                        .padding(.horizontal)
                    }

                    // Category breakdown
                    if !vm.categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Spending by Category")
                                .font(.headline)

                            CategoryBreakdownChart(breakdown: vm.categoryBreakdown)
                                .frame(height: 250)
                        }
                        .padding(.horizontal)
                    }

                    // Consumption sections (energy, water, gas, waste)
                    if !vm.consumptionSummaries.isEmpty {
                        ForEach(vm.consumptionSummaries, id: \.type) { summary in
                            ConsumptionSectionView(
                                type: summary.type,
                                currentMonth: summary.currentMonth,
                                previousMonth: summary.previousMonth,
                                trend: summary.trend,
                                unit: summary.unit
                            )
                            .padding(.horizontal)
                        }
                    }

                    if vm.totalDocuments == 0 && vm.consumptionSummaries.isEmpty {
                        DashboardPlaceholderView()
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
        .task {
            let vm = DashboardViewModel(database: database)
            vm.startObservation()
            viewModel = vm

            let docsVm = DocumentsViewModel(database: database)
            docsVm.startObservation()
            documentsViewModel = docsVm
        }
        .onDisappear {
            viewModel?.stopObservation()
            documentsViewModel?.stopObservation()
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }
}

struct CategoryBreakdownChart: View {
    let breakdown: [(category: SpendingCategory, amount: Double)]

    var body: some View {
        Chart {
            ForEach(breakdown, id: \.category.id) { item in
                BarMark(
                    x: .value("Amount", item.amount),
                    y: .value("Category", item.category.name)
                )
                .foregroundStyle(Color(hex: item.category.colorHex) ?? .blue)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(item.amount, format: .currency(code: "USD"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
    }
}

// MARK: - Placeholder for empty state

struct DashboardPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to Less")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Drop PDF receipts, credit card statements, or utility bills here to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Text("Configure your AI provider in Settings to enable document analysis.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color from hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
