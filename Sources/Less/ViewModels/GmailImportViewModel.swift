import Foundation
import Observation

@Observable @MainActor final class GmailImportViewModel {
    var isAuthorized = false
    var isSearching = false
    var isImporting = false
    var messages: [GmailMessage] = []
    var errorMessage: String?
    var importProgress: (current: Int, total: Int)?
    var alreadyImportedCount: Int = 0

    var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var endDate: Date = Date()

    private let oauthManager = GmailOAuthManager()
    private var importService: GmailImportService?
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func checkAuth() async {
        isAuthorized = await oauthManager.isAuthorized()
        if isAuthorized {
            importService = GmailImportService(oauthManager: oauthManager)
        }
    }

    func connectGmail() async {
        do {
            try await oauthManager.authorize()
            isAuthorized = true
            importService = GmailImportService(oauthManager: oauthManager)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectGmail() async {
        await oauthManager.signOut()
        isAuthorized = false
        importService = nil
        messages = []
    }

    func searchReceipts() async {
        guard let service = importService else { return }
        isSearching = true
        errorMessage = nil
        alreadyImportedCount = 0

        do {
            var results = try await service.searchReceipts(from: startDate, to: endDate)

            // Check which are already imported
            var imported = 0
            for i in results.indices {
                let hash = results[i].contentHash
                if (try? database.documentExists(fileHash: hash)) == true {
                    results[i].selected = false
                    imported += 1
                }
                // Also check PDF attachment hashes
                for attachment in results[i].attachments {
                    // We can't check the file hash without downloading, so skip
                }
            }
            alreadyImportedCount = imported

            messages = results
            dlog("Gmail search returned \(results.count) messages (\(imported) already imported)", category: "GmailImport")
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    func importSelected() async {
        guard let service = importService else { return }
        isImporting = true
        errorMessage = nil

        let selected = messages.filter(\.selected)
        importProgress = (current: 0, total: selected.count)

        let processor = DocumentProcessor(database: database)
        var errors: [String] = []

        for (index, message) in selected.enumerated() {
            importProgress = (current: index, total: selected.count)

            do {
                switch message.importType {
                case .pdfAttachment:
                    for attachment in message.attachments {
                        let url = try await service.downloadAttachment(attachment)
                        _ = try await processor.importDocument(url: url)
                    }

                case .inlineReceipt:
                    if let text = message.bodyText {
                        _ = try await processor.importEmailText(
                            subject: message.subject,
                            text: text,
                            date: message.date,
                            htmlData: message.bodyHTML
                        )
                    }
                }
            } catch DocumentProcessorError.duplicateDocument {
                // Skip silently
                dlog("Skipping duplicate: \(message.subject)", category: "GmailImport")
            } catch {
                errors.append("\(message.subject): \(error.localizedDescription)")
            }
        }

        importProgress = (current: selected.count, total: selected.count)

        if !errors.isEmpty {
            errorMessage = "Some imports failed:\n" + errors.prefix(5).joined(separator: "\n")
        }

        isImporting = false
    }

    var selectedCount: Int {
        messages.filter(\.selected).count
    }

    func selectAll() {
        for i in messages.indices { messages[i].selected = true }
    }

    func deselectAll() {
        for i in messages.indices { messages[i].selected = false }
    }
}
