import SwiftUI

struct SidebarView: View {
    @Environment(\.appDatabase) private var database
    @Binding var selection: SidebarSelection?
    @State private var viewModel: SidebarViewModel?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Dashboard", systemImage: "chart.bar")
                    .tag(SidebarSelection.dashboard)

                HStack {
                    Label("Insights", systemImage: "lightbulb")
                    if let count = viewModel?.pendingInsightCount, count > 0 {
                        Spacer()
                        Text("\(count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .tag(SidebarSelection.insights)

                HStack {
                    Label("Documents", systemImage: "doc.text")
                    if let count = viewModel?.documentCount, count > 0 {
                        Spacer()
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(SidebarSelection.documents)

                Label("All Line Items", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.lineItems)

                Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
                    .tag(SidebarSelection.askAI)
            }

            if let vm = viewModel, !vm.periods.isEmpty {
                Section("Recent Periods") {
                    ForEach(vm.periods.prefix(6), id: \.month) { period in
                        Label(periodLabel(year: period.year, month: period.month), systemImage: "calendar")
                            .tag(SidebarSelection.period(year: period.year, month: period.month))
                    }
                }
            }

            if let vm = viewModel, !vm.categories.isEmpty {
                Section("Categories") {
                    ForEach(vm.categories) { category in
                        Label(category.name, systemImage: category.icon)
                            .tag(SidebarSelection.category(category.id!))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Less is More")
        .task {
            let vm = SidebarViewModel(database: database)
            vm.startObservation()
            viewModel = vm
        }
        .onDisappear {
            viewModel?.stopObservation()
        }
    }

    private func periodLabel(year: Int, month: Int) -> String {
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
}
