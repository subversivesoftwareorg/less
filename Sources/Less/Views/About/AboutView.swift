import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            // App name and version
            VStack(spacing: 4) {
                Text("Less is More")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 200)

            // Purpose
            VStack(spacing: 12) {
                Text("Conscious Consumption")
                    .font(.headline)

                Text("""
                Less is More helps you see where your resources go \u{2014} money, \
                energy, water, and waste \u{2014} so you can make intentional \
                choices about what you consume.

                Import bills and receipts, capture them with your camera, \
                or log usage manually. It analyzes your patterns and \
                surfaces insights to help you reduce what you don't need.

                Your data stays on your machine, encrypted at rest. \
                AI analysis runs on-device by default. No accounts, \
                no cloud sync, no tracking.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 280)

            Divider()
                .frame(width: 200)

            // Company
            VStack(spacing: 4) {
                Text("Subversive Software")
                    .font(.callout)
                    .fontWeight(.medium)

                Text("Tools for intentional living.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 340, height: 480)
    }
}
