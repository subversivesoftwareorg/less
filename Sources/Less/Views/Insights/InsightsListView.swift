import SwiftUI

struct InsightsListView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: InsightsViewModel?
    @State private var selectedInsight: Insight?

    var body: some View {
        VSplitView {
            // Insights list (top)
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 12) {
                    // Filter
                    Picker(selection: Binding(
                        get: { viewModel?.filter ?? .pending },
                        set: { viewModel?.filter = $0 }
                    )) {
                        ForEach(InsightFilter.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    Spacer()

                    Picker("Sort", selection: Binding(
                        get: { viewModel?.sortOrder ?? .priority },
                        set: { viewModel?.sortOrder = $0 }
                    )) {
                        ForEach(InsightSort.allCases, id: \.self) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    .fixedSize()

                    Button {
                        viewModel?.runAnalysis()
                    } label: {
                        if viewModel?.isAnalyzing == true {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Analyze", systemImage: "sparkles")
                        }
                    }
                    .disabled(viewModel?.isAnalyzing == true)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if let vm = viewModel {
                    if vm.filteredInsights.isEmpty {
                        ContentUnavailableView {
                            Label("No Insights", systemImage: "lightbulb")
                        } description: {
                            if vm.insights.isEmpty {
                                Text("Click 'Analyze' to generate insights")
                            } else {
                                Text("No insights match the current filter")
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List(vm.filteredInsights, selection: $selectedInsight) { insight in
                            InsightRow(
                                insight: insight,
                                status: vm.reviewStatus(for: insight.id!)
                            )
                            .tag(insight)
                        }

                        // Scroll cue when there are more items than visible
                        if vm.filteredInsights.count > 5 {
                            HStack {
                                Spacer()
                                Text("\(vm.filteredInsights.count) insights")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if let error = vm.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Dismiss") { vm.errorMessage = nil }
                                .buttonStyle(.plain)
                                .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.05))
                    }
                }
            }
            .frame(minHeight: 250)

            // Detail pane (bottom)
            if let insight = selectedInsight, let vm = viewModel {
                InsightDetailView(
                    insight: insight,
                    status: vm.reviewStatus(for: insight.id!),
                    onUpdateStatus: { status, note in
                        vm.updateStatus(insight.id!, status: status, note: note)
                    }
                )
                .frame(minHeight: 180)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(.tertiary)
                        Text("Select an insight above")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            }
        }
        .task {
            let vm = InsightsViewModel(database: database)
            vm.startObservation()
            viewModel = vm
        }
        .onDisappear {
            viewModel?.stopObservation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runAnalysis)) { _ in
            viewModel?.runAnalysis()
        }
    }
}

struct InsightRow: View {
    let insight: Insight
    let status: ReviewStatus

    var body: some View {
        HStack(spacing: 10) {
            // Priority bar
            RoundedRectangle(cornerRadius: 2)
                .fill(severityColor)
                .frame(width: 3, height: 32)

            Image(systemName: insight.type.iconName)
                .foregroundStyle(severityColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(insight.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(insight.type.displayName)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.1), in: Capsule())
                .foregroundStyle(severityColor)
                .fixedSize()

            if status != .pending {
                Text(status.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1), in: Capsule())
                    .foregroundStyle(statusColor)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        switch insight.severity {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: .gray
        case .reviewed: .blue
        case .dismissed: .gray
        case .acted: .green
        }
    }
}

extension Insight: Hashable {
    static func == (lhs: Insight, rhs: Insight) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
