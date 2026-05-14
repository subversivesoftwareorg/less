import AVFoundation
import Foundation
import Observation

enum CaptureState {
    case previewing
    case capturing
    case reviewing(CapturedReceipt)
    case processing
    case error(String)
}

@Observable @MainActor final class ReceiptCaptureViewModel {
    var state: CaptureState = .previewing
    var guidance: CameraGuidance = .noDocument
    var currentDetection: DocumentDetectionResult?
    var isSessionRunning = false

    let cameraService = ReceiptCameraService()

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    var canCapture: Bool {
        if case .previewing = state {
            return guidance.isReadyToCapture
        }
        return false
    }

    func startCamera() async {
        let granted = await ReceiptCameraService.checkCameraPermission()
        guard granted else {
            state = .error(CameraError.permissionDenied.localizedDescription)
            return
        }

        do {
            try cameraService.setupSession()

            cameraService.onDocumentDetected = { [weak self] detection in
                Task { @MainActor in
                    self?.currentDetection = detection
                }
            }

            cameraService.onGuidanceChanged = { [weak self] newGuidance in
                Task { @MainActor in
                    self?.guidance = newGuidance
                }
            }

            cameraService.startSession()
            isSessionRunning = true
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stopCamera() {
        cameraService.stopSession()
        isSessionRunning = false
    }

    func capture() async {
        state = .capturing

        do {
            let rawImage = try await cameraService.capturePhoto()

            // Detect document boundary in full-res photo
            let detection = ReceiptCameraService.detectDocument(in: rawImage)

            // Apply perspective correction if document was detected
            let correctedImage: CGImage
            if let detection {
                correctedImage = ReceiptCameraService.correctPerspective(image: rawImage, detection: detection) ?? rawImage
            } else {
                correctedImage = rawImage
            }

            // Check OCR quality
            let (confidence, text) = await ReceiptCameraService.checkOCRQuality(image: correctedImage)

            let receipt = CapturedReceipt(
                originalImage: rawImage,
                correctedImage: correctedImage,
                ocrConfidence: confidence,
                extractedText: text
            )

            state = .reviewing(receipt)
            dlog("Capture complete: OCR confidence \(String(format: "%.0f%%", confidence * 100))", category: "Camera")

        } catch {
            state = .error("Capture failed: \(error.localizedDescription)")
        }
    }

    func retake() {
        state = .previewing
    }

    func accept() async {
        guard case .reviewing(let receipt) = state else { return }

        state = .processing

        // Convert to PDF
        guard let pdfURL = ReceiptCameraService.convertToPDF(image: receipt.correctedImage) else {
            state = .error("Failed to create PDF from captured image.")
            return
        }

        // Import through existing pipeline
        let vm = DocumentsViewModel(database: database)
        vm.importPDFs(urls: [pdfURL])

        // Give a moment for the import to start, then we can close
        try? await Task.sleep(for: .milliseconds(500))

        dlog("Receipt accepted and queued for import", category: "Camera")

        // Close the window
        NotificationCenter.default.post(name: .dismissCaptureWindow, object: nil)
    }

    var ocrQualityLevel: QualityLevel {
        guard case .reviewing(let receipt) = state else { return .unknown }
        if receipt.ocrConfidence > 0.6 { return .good }
        if receipt.ocrConfidence > 0.3 { return .fair }
        return .poor
    }

    enum QualityLevel {
        case good, fair, poor, unknown

        var description: String {
            switch self {
            case .good: "Text is readable"
            case .fair: "Text may be hard to read"
            case .poor: "Text is difficult to read — retake recommended"
            case .unknown: ""
            }
        }

        var iconName: String {
            switch self {
            case .good: "checkmark.circle.fill"
            case .fair: "exclamationmark.triangle.fill"
            case .poor: "xmark.circle.fill"
            case .unknown: "questionmark.circle"
            }
        }
    }
}

extension Notification.Name {
    static let dismissCaptureWindow = Notification.Name("dismissCaptureWindow")
}
