import SwiftUI

struct CategoryView: View {
    @Environment(\.appDatabase) private var database
    let categoryId: Int64
    @State private var category: SpendingCategory?
    @State private var lineItems: [LineItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let category {
                    // Header
                    HStack {
                        Image(systemName: category.icon)
                            .font(.title2)
                            .foregroundStyle(Color(hex: category.colorHex) ?? .blue)

                        Text(category.name)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        Text(total.formatted(.currency(code: "USD")))
                            .font(.title3)
                            .fontWeight(.bold)
                    }

                    Text("\(lineItems.count) transactions")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Divider()
                }

                if !lineItems.isEmpty {
                    ForEach(lineItems) { item in
                        LineItemRow(item: item)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Transactions", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("No spending in this category yet")
                    }
                }
            }
            .padding()
        }
        .task {
            loadData()
        }
    }

    private var total: Double {
        lineItems.reduce(0) { $0 + $1.amount }
    }

    private func loadData() {
        category = try? database.category(id: categoryId)
        lineItems = (try? database.lineItems(forCategory: categoryId)) ?? []
    }
}
