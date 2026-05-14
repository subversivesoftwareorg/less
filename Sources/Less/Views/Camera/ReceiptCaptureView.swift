import SwiftUI

struct ReceiptCaptureView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: ReceiptCaptureViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                captureContent(vm: vm)
            } else {
                ProgressView("Starting camera...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 550)
        .task {
            let vm = ReceiptCaptureViewModel(database: database)
            viewModel = vm
            await vm.startCamera()
        }
        .onDisappear {
            viewModel?.stopCamera()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissCaptureWindow)) { _ in
            viewModel?.stopCamera()
            // Close the window
            NSApp.keyWindow?.close()
        }
    }

    @ViewBuilder
    private func captureContent(vm: ReceiptCaptureViewModel) -> some View {
        VStack(spacing: 0) {
            switch vm.state {
            case .previewing, .capturing:
                previewState(vm: vm)
            case .reviewing(let receipt):
                reviewState(vm: vm, receipt: receipt)
            case .processing:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Processing receipt...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorState(message: message, vm: vm)
            }
        }
    }

    // MARK: - Preview State

    @ViewBuilder
    private func previewState(vm: ReceiptCaptureViewModel) -> some View {
        // Camera preview with overlay
        ZStack {
            CameraPreviewView(session: vm.cameraService.captureSession)
                .background(Color.black)

            DocumentOverlayView(detection: vm.currentDetection)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()

        // Guidance
        HStack(spacing: 8) {
            Circle()
                .fill(vm.guidance.isReadyToCapture ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            Text(vm.guidance.message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)

        // Capture button
        HStack {
            Spacer()

            Button {
                Task { await vm.capture() }
            } label: {
                HStack {
                    if case .capturing = vm.state {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "camera.fill")
                    }
                    Text("Capture")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!vm.canCapture)

            Spacer()
        }
        .padding()
    }

    // MARK: - Review State

    @ViewBuilder
    private func reviewState(vm: ReceiptCaptureViewModel, receipt: CapturedReceipt) -> some View {
        // Corrected image preview
        Image(nsImage: NSImage(cgImage: receipt.correctedImage,
                               size: NSSize(width: receipt.correctedImage.width,
                                            height: receipt.correctedImage.height)))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()

        // Quality indicators
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: vm.ocrQualityLevel.iconName)
                    .foregroundStyle(qualityColor(vm.ocrQualityLevel))
                Text("\(vm.ocrQualityLevel.description) (\(Int(receipt.ocrConfidence * 100))% confidence)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Document boundaries detected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !receipt.extractedText.isEmpty {
                DisclosureGroup("Preview extracted text") {
                    ScrollView {
                        Text(receipt.extractedText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 100)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)

        // Action buttons
        HStack(spacing: 16) {
            Button {
                vm.retake()
            } label: {
                Label("Retake", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button {
                Task { await vm.accept() }
            } label: {
                Label("Accept & Import", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Error State

    @ViewBuilder
    private func errorState(message: String, vm: ReceiptCaptureViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Try Again") {
                Task { await vm.startCamera() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func qualityColor(_ level: ReceiptCaptureViewModel.QualityLevel) -> Color {
        switch level {
        case .good: .green
        case .fair: .orange
        case .poor: .red
        case .unknown: .gray
        }
    }
}
