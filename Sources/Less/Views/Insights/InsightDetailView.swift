import SwiftUI

struct InsightDetailView: View {
    let insight: Insight
    let status: ReviewStatus
    let onUpdateStatus: (ReviewStatus, String) -> Void
    @State private var userNote: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    Image(systemName: insight.type.iconName)
                        .font(.title)
                        .foregroundStyle(severityColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        HStack(spacing: 12) {
                            Text(insight.type.displayName)
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(severityColor)
                                    .frame(width: 8, height: 8)
                                Text(insight.severity.rawValue.capitalized)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Text(insight.createdAt, format: .dateTime.month().day().year())
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Summary
                Text(insight.summary)
                    .font(.body)

                Divider()

                // Details
                if !insight.details.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.headline)

                        Text(insight.details)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Review actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review")
                        .font(.headline)

                    HStack {
                        Text("Status:")
                            .foregroundStyle(.secondary)

                        Text(status.displayName)
                            .fontWeight(.medium)
                            .foregroundStyle(statusColor)
                    }

                    TextField("Add a note (optional)...", text: $userNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    HStack(spacing: 12) {
                        if status == .pending {
                            Button {
                                onUpdateStatus(.reviewed, userNote)
                            } label: {
                                Label("Mark Reviewed", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                onUpdateStatus(.dismissed, userNote)
                            } label: {
                                Label("Dismiss", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                onUpdateStatus(.acted, userNote)
                            } label: {
                                Label("Acted On", systemImage: "star.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        } else {
                            Button {
                                onUpdateStatus(.pending, "")
                            } label: {
                                Label("Reopen", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
        }
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
