import Foundation

func dlog(_ message: String, category: String = "General", file: String = #file, function: String = #function) {
    guard AppSettings.shared.debugLoggingEnabled else { return }
    let filename = (file as NSString).lastPathComponent
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] [\(category)] \(filename):\(function) — \(message)")
}
