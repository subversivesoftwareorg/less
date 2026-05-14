import SwiftUI

struct LineItemsView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: LineItemsViewModel?
    @State private var searchText = ""

    let categoryId: Int64?

    init(categoryId: Int64? = nil) {
        self.categoryId = categoryId
    }

    var body: some View {
        VStack(spacing: 0) {
            if let vm = viewModel {
                // Header
                HStack {
                    Text("\(vm.filteredItems.count) items")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total: \(vm.totalAmount, format: .currency(code: "USD"))")
                        .fontWeight(.medium)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if vm.filteredItems.isEmpty {
                    ContentUnavailableView {
                        Label("No Line Items", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Import documents to see spending data here")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(vm.filteredItems) { item in
                        LineItemRow(item: item)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $searchText, prompt: "Filter items...")
        .onChange(of: searchText) { _, newValue in
            viewModel?.searchText = newValue
        }
        .task {
            let vm = LineItemsViewModel(database: database, categoryId: categoryId)
            vm.startObservation()
            viewModel = vm
        }
        .onDisappear {
            viewModel?.stopObservation()
        }
    }
}
