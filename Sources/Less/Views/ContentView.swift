import SwiftUI

enum SidebarSelection: Hashable {
    case dashboard
    case insights
    case documents
    case lineItems
    case askAI
    case period(year: Int, month: Int)
    case category(Int64)
}

struct ContentView: View {
    @Environment(\.appDatabase) private var database
    @State private var selection: SidebarSelection? = .dashboard
    @State private var showOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            Group {
                switch selection {
                case .dashboard:
                    DashboardView()
                case .insights:
                    InsightsListView()
                case .documents:
                    DocumentListView()
                case .lineItems:
                    LineItemsView()
                case .askAI:
                    AskAIView()
                case .period(let year, let month):
                    PeriodView(year: year, month: month)
                case .category(let id):
                    CategoryView(categoryId: id)
                case nil:
                    Text("Select an item from the sidebar")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .id(selection)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAskAI)) { _ in
            selection = .askAI
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, description: String)] = [
        (
            "eye",
            "Welcome to Less is More",
            "Make your spending and consumption visible. Less is More tracks where your resources go \u{2014} money, energy, water, and waste \u{2014} so you can make intentional choices about what you consume."
        ),
        (
            "doc.viewfinder",
            "Drop It In",
            "Scan your mail, photograph receipts, or save email statements as PDFs. Then drag and drop them into Less is More. The app extracts line items and categorizes your spending automatically using AI."
        ),
        (
            "chart.line.downtrend.xyaxis",
            "Insights Over Time",
            "As you add more documents, Less is More spots patterns and surfaces actionable ideas \u{2014} like subscriptions you forgot about, rising costs, or ways to cut waste. The more data it has, the sharper the insights."
        ),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: pages[currentPage].icon)
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.30, blue: 0.35),
                            Color(red: 0.10, green: 0.55, blue: 0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 60)

            Text(pages[currentPage].title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(pages[currentPage].description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer()

            // Dot indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Button {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    hasCompletedOnboarding = true
                    isPresented = false
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.08, green: 0.45, blue: 0.40))
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 480, height: 400)
        .interactiveDismissDisabled()
    }
}
