import Foundation
import CryptoKit
import PDFKit
import Vision

enum PDFExtractorError: LocalizedError {
    case cannotLoadPDF
    case noTextExtracted

    var errorDescription: String? {
        switch self {
        case .cannotLoadPDF: "Cannot load the PDF file."
        case .noTextExtracted: "No text could be extracted from the PDF."
        }
    }
}

enum PDFExtractor {
    /// Extract text from a PDF file. Tries PDFKit first, falls back to Vision OCR for scanned documents.
    static func extractText(from url: URL) async throws -> String {
        // Try PDFKit first (works for digital/text-based PDFs)
        if let text = extractWithPDFKit(url: url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dlog("Extracted \(text.count) chars via PDFKit from \(url.lastPathComponent)", category: "PDFExtractor")
            return text
        }

        // Fall back to Vision OCR (for scanned/image-based PDFs)
        let ocrText = try await extractWithVisionOCR(url: url)
        if !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dlog("Extracted \(ocrText.count) chars via Vision OCR from \(url.lastPathComponent)", category: "PDFExtractor")
            return ocrText
        }

        throw PDFExtractorError.noTextExtracted
    }

    /// Compute a SHA-256 hash of the file for deduplication.
    static func fileHash(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - PDFKit Extraction

    private static func extractWithPDFKit(url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text.isEmpty ? nil : text
    }

    // MARK: - Vision OCR Extraction

    private static func extractWithVisionOCR(url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractorError.cannotLoadPDF
        }

        var allText = ""

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)

            // Render page to CGImage
            let scale: CGFloat = 2.0
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { continue }

            context.setFillColor(CGColor.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)

            page.draw(with: .mediaBox, to: context)

            guard let cgImage = context.makeImage() else { continue }

            let pageText = try await recognizeText(in: cgImage)
            allText += pageText + "\n"
        }

        return allText
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
