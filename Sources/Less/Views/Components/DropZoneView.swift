import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop PDF files here")
                .font(.title3)
                .foregroundStyle(isTargeted ? .primary : .secondary)

            Text("Receipts, statements, bills")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                )
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Try loading as a file URL first (most reliable for Finder drops)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url, url.pathExtension.lowercased() == "pdf" {
                        dlog("Drop received file URL: \(url.path)", category: "DropZone")
                        DispatchQueue.main.async {
                            onDrop([url])
                        }
                    } else if let error {
                        dlog("Drop URL load error: \(error)", category: "DropZone")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                    if let url {
                        // loadFileRepresentation gives a temporary URL — copy it to persist
                        let tempDir = FileManager.default.temporaryDirectory
                        let dest = tempDir.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.removeItem(at: dest)
                        do {
                            try FileManager.default.copyItem(at: url, to: dest)
                            dlog("Drop received PDF (copied to temp): \(dest.path)", category: "DropZone")
                            DispatchQueue.main.async {
                                onDrop([dest])
                            }
                        } catch {
                            dlog("Drop copy error: \(error)", category: "DropZone")
                        }
                    } else if let error {
                        dlog("Drop PDF load error: \(error)", category: "DropZone")
                    }
                }
            }
        }
        return true
    }
}
