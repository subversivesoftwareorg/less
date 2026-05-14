@preconcurrency import AVFoundation
import CoreImage
import Foundation
import PDFKit
import Vision

// MARK: - Data Types

struct DocumentDetectionResult: Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let confidence: Float
    let documentSizeFraction: Double
}

struct CapturedReceipt: Sendable {
    let originalImage: CGImage
    let correctedImage: CGImage
    let ocrConfidence: Double
    let extractedText: String
}

enum CameraGuidance: Sendable {
    case noDocument
    case tooFar
    case tooClose
    case holdSteady
    case lensSmudge

    var message: String {
        switch self {
        case .noDocument: "Position receipt within the camera view"
        case .tooFar: "Move closer to fill more of the frame"
        case .tooClose: "Move back — receipt may be cropped"
        case .holdSteady: "Hold steady — receipt detected"
        case .lensSmudge: "Clean camera lens for better results"
        }
    }

    var isReadyToCapture: Bool {
        self == .holdSteady || self == .lensSmudge
    }
}

// MARK: - Camera Service

final class ReceiptCameraService: NSObject, Sendable {
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.less.camera.processing")

    // Callbacks (set by view model)
    nonisolated(unsafe) var onDocumentDetected: ((DocumentDetectionResult?) -> Void)?
    nonisolated(unsafe) var onGuidanceChanged: ((CameraGuidance) -> Void)?
    nonisolated(unsafe) private var photoContinuation: CheckedContinuation<CGImage, Error>?

    // MARK: - Session Setup

    func setupSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .photo

        // Find camera (prefer Continuity Camera for better quality)
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.noCameraAvailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        captureSession.addInput(input)

        // Photo output
        guard captureSession.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddOutput
        }
        captureSession.addOutput(photoOutput)

        // Video output for real-time frame analysis
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.cannotAddOutput
        }
        captureSession.addOutput(videoOutput)

        dlog("Camera session configured", category: "Camera")
    }

    func startSession() {
        guard !captureSession.isRunning else { return }
        captureSession.startRunning()
        dlog("Camera session started", category: "Camera")
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
        dlog("Camera session stopped", category: "Camera")
    }

    // MARK: - Photo Capture

    func capturePhoto() async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Document Detection

    private func detectDocument(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            dlog("Document detection failed: \(error)", category: "Camera")
            return
        }

        guard let result = request.results?.first else {
            onDocumentDetected?(nil)
            onGuidanceChanged?(.noDocument)
            return
        }

        let topLeft = result.topLeft
        let topRight = result.topRight
        let bottomLeft = result.bottomLeft
        let bottomRight = result.bottomRight

        // Calculate document size as fraction of frame
        let width = max(
            hypot(topRight.x - topLeft.x, topRight.y - topLeft.y),
            hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y)
        )
        let height = max(
            hypot(bottomLeft.x - topLeft.x, bottomLeft.y - topLeft.y),
            hypot(bottomRight.x - topRight.x, bottomRight.y - topRight.y)
        )
        let sizeFraction = Double(width * height)

        let detection = DocumentDetectionResult(
            topLeft: CGPoint(x: topLeft.x, y: topLeft.y),
            topRight: CGPoint(x: topRight.x, y: topRight.y),
            bottomLeft: CGPoint(x: bottomLeft.x, y: bottomLeft.y),
            bottomRight: CGPoint(x: bottomRight.x, y: bottomRight.y),
            confidence: result.confidence,
            documentSizeFraction: sizeFraction
        )

        onDocumentDetected?(detection)

        // Determine guidance
        if sizeFraction < 0.15 {
            onGuidanceChanged?(.tooFar)
        } else if sizeFraction > 0.95 {
            onGuidanceChanged?(.tooClose)
        } else {
            onGuidanceChanged?(.holdSteady)
        }
    }

    // MARK: - Perspective Correction

    static func correctPerspective(image: CGImage, detection: DocumentDetectionResult) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        // Convert normalized coordinates to pixel coordinates
        // Vision uses bottom-left origin, same as Core Image
        filter.setValue(CIVector(x: detection.topLeft.x * imageWidth,
                                y: detection.topLeft.y * imageHeight),
                       forKey: "inputTopLeft")
        filter.setValue(CIVector(x: detection.topRight.x * imageWidth,
                                y: detection.topRight.y * imageHeight),
                       forKey: "inputTopRight")
        filter.setValue(CIVector(x: detection.bottomLeft.x * imageWidth,
                                y: detection.bottomLeft.y * imageHeight),
                       forKey: "inputBottomLeft")
        filter.setValue(CIVector(x: detection.bottomRight.x * imageWidth,
                                y: detection.bottomRight.y * imageHeight),
                       forKey: "inputBottomRight")

        let context = CIContext()
        guard let outputImage = filter.outputImage,
              let cgResult = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return cgResult
    }

    // MARK: - OCR Quality Check

    static func checkOCRQuality(image: CGImage) async -> (confidence: Double, text: String) {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(returning: (0, ""))
                    return
                }

                var totalConfidence: Float = 0
                var textParts: [String] = []

                for obs in observations {
                    if let candidate = obs.topCandidates(1).first {
                        totalConfidence += candidate.confidence
                        textParts.append(candidate.string)
                    }
                }

                let avgConfidence = Double(totalConfidence) / Double(observations.count)
                let fullText = textParts.joined(separator: "\n")
                continuation.resume(returning: (avgConfidence, fullText))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: (0, ""))
            }
        }
    }

    // MARK: - Full-res Document Detection

    static func detectDocument(in image: CGImage) -> DocumentDetectionResult? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let result = request.results?.first else { return nil }

        return DocumentDetectionResult(
            topLeft: CGPoint(x: result.topLeft.x, y: result.topLeft.y),
            topRight: CGPoint(x: result.topRight.x, y: result.topRight.y),
            bottomLeft: CGPoint(x: result.bottomLeft.x, y: result.bottomLeft.y),
            bottomRight: CGPoint(x: result.bottomRight.x, y: result.bottomRight.y),
            confidence: result.confidence,
            documentSizeFraction: 1.0
        )
    }

    // MARK: - Convert to PDF

    static func convertToPDF(image: CGImage) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "receipt-\(ISO8601DateFormatter().string(from: Date())).pdf"
            .replacingOccurrences(of: ":", with: "-")
        let pdfURL = tempDir.appendingPathComponent(filename)

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Scale to reasonable page size (max 8.5x11 inches at 72dpi)
        let maxWidth: CGFloat = 612  // 8.5 inches
        let maxHeight: CGFloat = 792 // 11 inches
        let scale = min(maxWidth / width, maxHeight / height, 1.0)
        let pageWidth = width * scale
        let pageHeight = height * scale

        let pdfPage = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: pageWidth, height: pageHeight)))
        let pdfDocument = PDFDocument()

        guard let page = pdfPage else { return nil }
        pdfDocument.insert(page, at: 0)
        pdfDocument.write(to: pdfURL)

        dlog("Saved receipt PDF: \(pdfURL.path)", category: "Camera")
        return pdfURL
    }

    // MARK: - Permission Check

    static func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ReceiptCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        detectDocument(in: pixelBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension ReceiptCameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            photoContinuation?.resume(throwing: CameraError.captureProcessingFailed)
            photoContinuation = nil
            return
        }

        photoContinuation?.resume(returning: cgImage)
        photoContinuation = nil
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput
    case permissionDenied
    case captureProcessingFailed

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: "No camera found. Connect a camera or use Continuity Camera with your iPhone."
        case .cannotAddInput: "Cannot configure camera input."
        case .cannotAddOutput: "Cannot configure camera output."
        case .permissionDenied: "Camera access denied. Enable it in System Settings > Privacy & Security > Camera."
        case .captureProcessingFailed: "Failed to process captured photo."
        }
    }
}
