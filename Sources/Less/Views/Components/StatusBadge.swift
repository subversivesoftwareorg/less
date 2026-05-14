import SwiftUI

struct StatusBadge: View {
    let status: ProcessingStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1), in: Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .pending: .gray
        case .extractingText, .awaitingAI, .processing: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}
