import Foundation

// MARK: - Google Cloud Setup Instructions
//
// 1. Go to https://console.cloud.google.com/apis/credentials
// 2. Create a new project (or select existing)
// 3. Enable the "Gmail API" under APIs & Services > Library
// 4. Create an OAuth 2.0 Client ID:
//    - Application type: Desktop app
//    - Add http://127.0.0.1:8850 as an authorized redirect URI
// 5. Enter the Client ID and Client Secret in Less Settings

enum GmailConfig {
    // These are read from UserDefaults — user enters them in Settings
    static var clientId: String {
        UserDefaults.standard.string(forKey: "gmailClientId") ?? ""
    }
    static var clientSecret: String {
        UserDefaults.standard.string(forKey: "gmailClientSecret") ?? ""
    }

    static let scopes = ["https://www.googleapis.com/auth/gmail.readonly"]

    static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenURL = "https://oauth2.googleapis.com/token"
    static let gmailAPIBase = "https://gmail.googleapis.com"

    static let loopbackPort: UInt16 = 8850
    static var redirectURI: String { "http://127.0.0.1:\(loopbackPort)" }

    static var isConfigured: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }
}
