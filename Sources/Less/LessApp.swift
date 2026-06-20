import SwiftUI
import AppKit
import Sparkle
import UserNotifications

@main
struct LessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appDatabase: AppDatabase
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    init() {
        do {
            let db = AppDatabase.shared
            _appDatabase = State(wrappedValue: db)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, appDatabase)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Less is More") {
                    NSApp.sendAction(#selector(AppDelegate.showAbout), to: nil, from: nil)
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Import Documents...") {
                    NotificationCenter.default.post(name: .importDocuments, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Capture Receipt...") {
                    NotificationCenter.default.post(name: .captureReceipt, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Log Consumption...") {
                    NotificationCenter.default.post(name: .logConsumption, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Divider()


            }
            CommandGroup(after: .sidebar) {
                Button("Show Dashboard") {
                    NotificationCenter.default.post(name: .showDashboard, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Show Insights") {
                    NotificationCenter.default.post(name: .showInsights, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(after: .importExport) {
                Button("Run Analysis...") {
                    NotificationCenter.default.post(name: .runAnalysis, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        .defaultSize(width: 1200, height: 800)

        Window("Capture Receipt", id: "receipt-capture") {
            ReceiptCaptureView()
                .environment(\.appDatabase, appDatabase)
        }
        .defaultSize(width: 560, height: 620)

        Window("Log Consumption", id: "manual-entry") {
            ManualEntryView()
                .environment(\.appDatabase, appDatabase)
        }
        .defaultSize(width: 450, height: 420)

        Settings {
            SettingsView()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "less", url.host == "import-email" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filePath = components.queryItems?.first(where: { $0.name == "file" })?.value else {
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        Task {
            defer { try? FileManager.default.removeItem(at: fileURL) }

            guard let data = try? Data(contentsOf: fileURL),
                  let payload = try? JSONDecoder().decode(EmailPayload.self, from: data) else {
                return
            }

            let processor = DocumentProcessor(database: appDatabase)
            let date = Date(timeIntervalSince1970: payload.dateTimestamp)
            _ = try? await processor.importEmailText(
                subject: payload.subject,
                text: payload.body,
                date: date,
                htmlData: nil
            )

            NotificationCenter.default.post(name: .emailImported, object: nil)

            let content = UNMutableNotificationContent()
            content.title = "Email Imported"
            content.body = payload.subject
            let request = UNNotificationRequest(
                identifier: "email-import-\(Date.now.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

private struct EmailPayload: Codable {
    let subject: String
    let body: String
    let sender: String
    let dateTimestamp: TimeInterval
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func showAbout() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "about-less" }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("about-less")
        window.title = "About Less is More"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let importDocuments = Notification.Name("importDocuments")
    static let showDashboard = Notification.Name("showDashboard")
    static let showInsights = Notification.Name("showInsights")
    static let runAnalysis = Notification.Name("runAnalysis")
    static let captureReceipt = Notification.Name("captureReceipt")
    static let logConsumption = Notification.Name("logConsumption")
    static let emailImported = Notification.Name("emailImported")
}
