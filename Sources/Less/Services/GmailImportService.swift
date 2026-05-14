import Foundation
import CryptoKit

// MARK: - Data Types

struct GmailMessage: Identifiable {
    let id: String
    let subject: String
    let from: String
    let date: Date
    let snippet: String
    let attachments: [GmailAttachment]
    let bodyText: String?         // extracted text from HTML body
    let bodyHTML: Data?           // raw HTML for storage
    var selected: Bool = true

    var importType: ImportType {
        if !attachments.isEmpty { return .pdfAttachment }
        return .inlineReceipt
    }

    var contentHash: String {
        let content = "\(id)-\(subject)-\(from)"
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    enum ImportType {
        case pdfAttachment
        case inlineReceipt
    }
}

struct GmailAttachment: Identifiable {
    let id: String
    let messageId: String
    let filename: String
    let mimeType: String
    let size: Int
}

// MARK: - Service

actor GmailImportService {
    private let oauthManager: GmailOAuthManager

    init(oauthManager: GmailOAuthManager) {
        self.oauthManager = oauthManager
    }

    /// Search for receipt-like emails in a date range.
    func searchReceipts(from startDate: Date, to endDate: Date) async throws -> [GmailMessage] {
        let token = try await oauthManager.validAccessToken()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let after = dateFormatter.string(from: startDate)
        let before = dateFormatter.string(from: endDate)

        // Two queries: PDF attachments + inline receipts
        let queries = [
            "has:attachment filename:pdf after:\(after) before:\(before)",
            "after:\(after) before:\(before) (receipt OR invoice OR \"order confirmation\" OR \"your order\" OR \"payment received\" OR \"billing statement\" OR \"your receipt\")",
        ]

        var allMessageIds: Set<String> = []
        for query in queries {
            let ids = try await searchMessageIds(query: query, token: token)
            allMessageIds.formUnion(ids)
        }

        dlog("Gmail search found \(allMessageIds.count) unique messages", category: "GmailImport")

        // Fetch message details in parallel (batches of 10)
        var messages: [GmailMessage] = []
        let idArray = Array(allMessageIds)

        for batch in stride(from: 0, to: idArray.count, by: 10) {
            let batchIds = Array(idArray[batch..<min(batch + 10, idArray.count)])
            let batchMessages = try await withThrowingTaskGroup(of: GmailMessage?.self) { group in
                for msgId in batchIds {
                    group.addTask {
                        try await self.fetchMessage(id: msgId, token: token)
                    }
                }
                var results: [GmailMessage] = []
                for try await msg in group {
                    if let msg { results.append(msg) }
                }
                return results
            }
            messages.append(contentsOf: batchMessages)
        }

        // Sort by date descending
        messages.sort { $0.date > $1.date }
        return messages
    }

    /// Download a PDF attachment to a temp file.
    func downloadAttachment(_ attachment: GmailAttachment) async throws -> URL {
        let token = try await oauthManager.validAccessToken()

        let urlString = "\(GmailConfig.gmailAPIBase)/gmail/v1/users/me/messages/\(attachment.messageId)/attachments/\(attachment.id)"
        guard let url = URL(string: urlString) else {
            throw GmailImportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64Data = json["data"] as? String else {
            throw GmailImportError.attachmentDownloadFailed
        }

        // Gmail uses base64url encoding (- instead of +, _ instead of /)
        let base64Standard = base64Data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let fileData = Data(base64Encoded: base64Standard) else {
            throw GmailImportError.attachmentDecodeFailed
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(attachment.filename)
        try fileData.write(to: tempURL)

        dlog("Downloaded attachment: \(attachment.filename) (\(fileData.count) bytes)", category: "GmailImport")
        return tempURL
    }

    // MARK: - Private API Calls

    private func searchMessageIds(query: String, token: String) async throws -> [String] {
        var allIds: [String] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "\(GmailConfig.gmailAPIBase)/gmail/v1/users/me/messages")!
            var queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: "100"),
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

            if let messages = json["messages"] as? [[String: Any]] {
                let ids = messages.compactMap { $0["id"] as? String }
                allIds.append(contentsOf: ids)
            }

            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil

        return allIds
    }

    private func fetchMessage(id: String, token: String) async throws -> GmailMessage? {
        let urlString = "\(GmailConfig.gmailAPIBase)/gmail/v1/users/me/messages/\(id)?format=full"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Extract headers
        let headers = extractHeaders(from: json)
        let subject = headers["Subject"] ?? "(no subject)"
        let from = headers["From"] ?? ""
        let dateString = headers["Date"] ?? ""
        let snippet = json["snippet"] as? String ?? ""

        // Parse date
        let date = parseEmailDate(dateString) ?? Date()

        // Find PDF attachments
        var attachments: [GmailAttachment] = []
        if let payload = json["payload"] as? [String: Any] {
            findAttachments(in: payload, messageId: id, attachments: &attachments)
        }

        // Extract body text for inline receipts
        var bodyText: String?
        var bodyHTML: Data?
        if attachments.isEmpty {
            if let payload = json["payload"] as? [String: Any] {
                let (text, html) = extractBody(from: payload)
                if let text, !text.isEmpty {
                    bodyText = text
                    bodyHTML = html
                }
            }
        }

        // Skip messages that have neither attachments nor body text
        if attachments.isEmpty && bodyText == nil { return nil }

        return GmailMessage(
            id: id,
            subject: subject,
            from: from,
            date: date,
            snippet: snippet,
            attachments: attachments,
            bodyText: bodyText,
            bodyHTML: bodyHTML
        )
    }

    private func extractHeaders(from json: [String: Any]) -> [String: String] {
        guard let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for header in headers {
            if let name = header["name"] as? String, let value = header["value"] as? String {
                result[name] = value
            }
        }
        return result
    }

    private func findAttachments(in part: [String: Any], messageId: String, attachments: inout [GmailAttachment]) {
        let mimeType = part["mimeType"] as? String ?? ""
        let filename = part["filename"] as? String ?? ""

        if !filename.isEmpty && mimeType == "application/pdf" {
            if let body = part["body"] as? [String: Any],
               let attachmentId = body["attachmentId"] as? String {
                let size = body["size"] as? Int ?? 0
                attachments.append(GmailAttachment(
                    id: attachmentId,
                    messageId: messageId,
                    filename: filename,
                    mimeType: mimeType,
                    size: size
                ))
            }
        }

        // Recurse into parts
        if let parts = part["parts"] as? [[String: Any]] {
            for subPart in parts {
                findAttachments(in: subPart, messageId: messageId, attachments: &attachments)
            }
        }
    }

    private func extractBody(from payload: [String: Any]) -> (text: String?, html: Data?) {
        // Try to find text/plain or text/html parts
        var plainText: String?
        var htmlData: Data?

        func search(part: [String: Any]) {
            let mimeType = part["mimeType"] as? String ?? ""

            if mimeType == "text/plain" || mimeType == "text/html" {
                if let body = part["body"] as? [String: Any],
                   let base64Data = body["data"] as? String {
                    let decoded = base64Data
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    if let data = Data(base64Encoded: decoded) {
                        if mimeType == "text/plain" {
                            plainText = String(data: data, encoding: .utf8)
                        } else {
                            htmlData = data
                            // Also extract text from HTML as fallback
                            if plainText == nil, let html = String(data: data, encoding: .utf8) {
                                plainText = stripHTML(html)
                            }
                        }
                    }
                }
            }

            if let parts = part["parts"] as? [[String: Any]] {
                for subPart in parts { search(part: subPart) }
            }
        }

        search(part: payload)
        return (plainText, htmlData)
    }

    private func stripHTML(_ html: String) -> String {
        // Simple HTML tag stripping — enough for receipt text extraction
        var text = html
        // Remove style and script blocks
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        // Replace br/p/div/tr with newlines
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</td>", with: "\t", options: .caseInsensitive)
        // Strip remaining tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse whitespace
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseEmailDate(_ dateString: String) -> Date? {
        let formatters: [DateFormatter] = {
            let formats = [
                "EEE, dd MMM yyyy HH:mm:ss Z",
                "dd MMM yyyy HH:mm:ss Z",
                "EEE, dd MMM yyyy HH:mm:ss z",
            ]
            return formats.map { format in
                let f = DateFormatter()
                f.dateFormat = format
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }
        }()
        for formatter in formatters {
            if let date = formatter.date(from: dateString) { return date }
        }
        return nil
    }
}

// MARK: - Errors

enum GmailImportError: LocalizedError {
    case invalidURL
    case attachmentDownloadFailed
    case attachmentDecodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Gmail API URL."
        case .attachmentDownloadFailed: "Failed to download attachment from Gmail."
        case .attachmentDecodeFailed: "Failed to decode attachment data."
        }
    }
}
