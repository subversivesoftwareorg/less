import Foundation
import Observation
import GRDB

@Observable final class DocumentsViewModel {
    var documents: [Document] = []
    var isImporting = false
    var errorMessage: String?

    private let database: AppDatabase
    private let processor: DocumentProcessor
    private var observationTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        self.processor = DocumentProcessor(database: database)
        self.documents = (try? database.allDocuments()) ?? []
    }

    func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let observation = ValueObservation.tracking { db in
                try Document.order(Column("importedAt").desc).fetchAll(db)
            }
            do {
                for try await docs in observation.values(in: database.dbQueue) {
                    self.documents = docs
                }
            } catch {
                dlog("Document observation error: \(error)", category: "DocumentsViewModel")
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }

    func importPDFs(urls: [URL]) {
        isImporting = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            var errors: [String] = []

            for url in urls {
                do {
                    // Access security-scoped resource if needed
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                    _ = try await self.processor.importDocument(url: url)
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    dlog("Import failed for \(url.lastPathComponent): \(error)", category: "DocumentsViewModel")
                }
            }

            self.isImporting = false
            if !errors.isEmpty {
                self.errorMessage = errors.joined(separator: "\n")
            }
        }
    }

    func deleteDocument(_ document: Document) {
        guard let id = document.id else { return }
        do {
            try database.deleteDocument(id)
        } catch {
            dlog("Delete failed: \(error)", category: "DocumentsViewModel")
        }
    }
}
