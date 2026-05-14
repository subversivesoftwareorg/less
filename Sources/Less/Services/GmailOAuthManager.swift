import Foundation
import Network
import AppKit

actor GmailOAuthManager {
    private static let keychainAccount = "gmail_oauth_tokens"

    struct StoredTokens: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    enum OAuthError: LocalizedError {
        case notConfigured
        case authorizationFailed(String)
        case tokenExchangeFailed(String)
        case refreshFailed
        case serverStartFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Gmail OAuth not configured. Enter your Google Cloud Client ID and Secret in Settings."
            case .authorizationFailed(let reason):
                return "Gmail authorization failed: \(reason)"
            case .tokenExchangeFailed(let reason):
                return "Token exchange failed: \(reason)"
            case .refreshFailed:
                return "Gmail token refresh failed. Please reconnect."
            case .serverStartFailed:
                return "Could not start local OAuth callback server on port \(GmailConfig.loopbackPort)."
            }
        }
    }

    func isAuthorized() -> Bool {
        KeychainHelper.exists(account: Self.keychainAccount)
    }

    func authorize() async throws {
        guard GmailConfig.isConfigured else {
            throw OAuthError.notConfigured
        }

        let code = try await startLoopbackAndGetCode()
        let tokens = try await exchangeCodeForTokens(code)
        try storeTokens(tokens)
        dlog("Gmail OAuth authorized", category: "GmailOAuth")
    }

    func validAccessToken() async throws -> String {
        let tokens = try loadTokens()

        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }

        let refreshed = try await refreshAccessToken(tokens.refreshToken)
        try storeTokens(refreshed)
        return refreshed.accessToken
    }

    func signOut() {
        KeychainHelper.delete(account: Self.keychainAccount)
        dlog("Gmail OAuth signed out", category: "GmailOAuth")
    }

    // MARK: - Loopback Server

    private func startLoopbackAndGetCode() async throws -> String {
        let port = NWEndpoint.Port(rawValue: GmailConfig.loopbackPort)!
        let listener = try NWListener(using: .tcp, on: port)

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func tryResume(with result: Result<String, Error>) {
                lock.lock()
                let shouldResume = !resumed
                if shouldResume { resumed = true }
                lock.unlock()
                guard shouldResume else { return }
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    defer { listener.cancel() }

                    guard let data, let request = String(data: data, encoding: .utf8) else {
                        tryResume(with: .failure(OAuthError.authorizationFailed("No data received")))
                        return
                    }

                    guard let codeLine = request.split(separator: "\r\n").first,
                          let urlPart = codeLine.split(separator: " ").dropFirst().first,
                          let components = URLComponents(string: String(urlPart)),
                          let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                        let errorMsg = URLComponents(string: String(request.split(separator: " ").dropFirst().first ?? ""))?
                            .queryItems?.first(where: { $0.name == "error" })?.value ?? "unknown"
                        let html = "<html><body><h2>Authorization failed</h2><p>\(errorMsg)</p></body></html>"
                        self.sendHTTPResponse(connection: connection, html: html)
                        tryResume(with: .failure(OAuthError.authorizationFailed(errorMsg)))
                        return
                    }

                    let html = "<html><body><h2>Authorization successful!</h2><p>You can close this tab and return to Less.</p></body></html>"
                    self.sendHTTPResponse(connection: connection, html: html)
                    tryResume(with: .success(code))
                }
            }

            listener.stateUpdateHandler = { state in
                if case .failed = state {
                    tryResume(with: .failure(OAuthError.serverStartFailed))
                }
            }

            listener.start(queue: .global())

            var components = URLComponents(string: GmailConfig.authURL)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: GmailConfig.clientId),
                URLQueryItem(name: "redirect_uri", value: GmailConfig.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: GmailConfig.scopes.joined(separator: " ")),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]

            if let url = components.url {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private nonisolated func sendHTTPResponse(connection: NWConnection, html: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: response.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(_ code: String) async throws -> StoredTokens {
        var request = URLRequest(url: URL(string: GmailConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "code=\(code)",
            "client_id=\(GmailConfig.clientId)",
            "client_secret=\(GmailConfig.clientSecret)",
            "redirect_uri=\(GmailConfig.redirectURI)",
            "grant_type=authorization_code",
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed(body)
        }

        return StoredTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> StoredTokens {
        var request = URLRequest(url: URL(string: GmailConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "refresh_token=\(refreshToken)",
            "client_id=\(GmailConfig.clientId)",
            "client_secret=\(GmailConfig.clientSecret)",
            "grant_type=refresh_token",
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw OAuthError.refreshFailed
        }

        return StoredTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    private func storeTokens(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try KeychainHelper.save(data, account: Self.keychainAccount)
    }

    private func loadTokens() throws -> StoredTokens {
        let data = try KeychainHelper.load(account: Self.keychainAccount)
        return try JSONDecoder().decode(StoredTokens.self, from: data)
    }
}
