import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(\.appDatabase) private var database
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: DashboardViewModel?
    @State private var documentsViewModel: DocumentsViewModel?
    @State private var dismissedAIWarning = false

    private var aiWarning: (message: String, detail: String)? {
        guard !dismissedAIWarning else { return nil }
        let settings = AppSettings.shared

        if settings.selectedProvider == "ondevice" {
            if !LLMProviderFactory.onDeviceAvailable {
                let reason = LLMProviderFactory.onDeviceUnavailableReason ?? "On-device AI is unavailable."
                return (
                    reason,
                    "Less is More needs AI to analyze your documents. Configure a cloud provider (Anthropic or OpenAI-compatible) in Settings, or update to macOS 26 with Apple Intelligence enabled."
                )
            }
        } else {
            if LLMProviderFactory.create() == nil {
                return (
                    "No API key configured for \(settings.selectedProvider == "anthropic" ? "Anthropic" : "your cloud provider").",
                    "Less is More needs an AI provider to analyze documents. Add your API key in Settings."
                )
            }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // AI provider warning
                if let warning = aiWarning {
                    AIWarningBanner(
                        message: warning.message,
                        detail: warning.detail,
                        onDismiss: { dismissedAIWarning = true }
                    )
                    .padding(.horizontal)
                }

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

// MARK: - AI Warning Banner

struct AIWarningBanner: View {
    let message: String
    let detail: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings\u{2026}") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .font(.caption)
                .padding(.top, 2)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Placeholder for empty state

struct DashboardPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to Less is More")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Drop PDF receipts, credit card statements, or utility bills here to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)
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
