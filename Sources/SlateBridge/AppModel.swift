import AppKit
import BridgeCore
import BridgeSources
import BridgeWriter
import Contacts
import EventKit
import Foundation
import os
import ServiceManagement

/// The app's state and its one job: run a sync at launch, every 15 minutes,
/// on Sync Now, on wake, and soon after either store says it changed (§6.1).
/// One run at a time; a request during a run becomes one more run after it.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings { didSet { if settings != oldValue { settings.save() } } }
    @Published private(set) var syncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var events = 0
    @Published private(set) var contacts = 0
    @Published private(set) var problems: [String] = []
    /// Accounts whose empty read is waiting on "Confirm deletions".
    @Published private(set) var unconfirmed: [String] = []
    @Published private(set) var access = (calendars: false, contacts: false)
    /// Moves once a minute so "Synced 4 min ago" stays true.
    @Published private(set) var now = Date()

    let sources = LiveSources()
    private let log = Logger(subsystem: "slate-bridge-mac", category: "sync")
    private var again = false
    private var soon: Task<Void, Never>?
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        settings = AppSettings.load()
    }

    // MARK: - Starting

    func start() {
        Task {
            // The first time, this is where macOS asks.
            let granted = await sources.requestAccess()
            access = granted
            if settings.selection == nil, granted.calendars, granted.contacts {
                settings.selection = sources.defaultSelection()
            }
            syncNow()
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        })
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .CNContactStoreDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncSoon() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncSoon() }
        })
    }

    /// A store says something changed: wait for it to settle, then sync once.
    func syncSoon(after seconds: Double = 10) {
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    // MARK: - Syncing

    func syncNow(confirming: Set<String> = []) {
        guard !syncing else {
            again = true
            return
        }
        guard access.calendars || access.contacts else {
            problems = ["No access to Calendars or Contacts: allow Slate Bridge in System Settings → Privacy & Security."]
            return
        }
        var s = settings
        let vault: URL
        do {
            guard let v = try VaultAccess.resolve(&s) else {
                problems = ["Choose your vault in Settings."]
                return
            }
            vault = v
        } catch {
            problems = ["The vault could not be found: \(error.localizedDescription). Choose it again in Settings."]
            return
        }
        settings = s
        guard let selection = s.selection else {
            problems = ["Waiting for access to Calendars and Contacts."]
            return
        }

        syncing = true
        let sources = self.sources
        let log = self.log
        Task.detached {
            let scoped = vault.startAccessingSecurityScopedResource()
            defer { if scoped { vault.stopAccessingSecurityScopedResource() } }
            let (window, firstDay) = Window.around(Date(), monthsBack: s.monthsBack, monthsAhead: s.monthsAhead)
            var options = SyncOptions()
            options.attendeeCap = s.attendeeCap
            options.windowStart = firstDay
            options.confirmedEmpty = confirming
            let result: Result<SyncReport, Error> = Result {
                let accounts = sources.read(selection, window: window, folders: s.folders)
                return try Sync.run(vault: vault, store: .standard(vault: vault), accounts: accounts, options: options)
            }
            switch result {
            case .success(let r): log.info("\(r.description, privacy: .private)")
            case .failure(let e): log.error("sync failed: \(String(describing: e), privacy: .public)")
            }
            Self.writeLog(result)
            await MainActor.run { [weak self] in self?.finish(result) }
        }
    }

    private func finish(_ result: Result<SyncReport, Error>) {
        syncing = false
        switch result {
        case .success(let r):
            lastSync = Date()
            events = r.events
            contacts = r.contacts
            problems = r.problems
            unconfirmed = r.unconfirmedEmpty
        case .failure(let e):
            problems = ["The sync failed: \(e)"]
        }
        now = Date()
        if again {
            again = false
            syncNow()
        }
    }

    /// The last run's report, beside the app's other logs, for reading when
    /// the menu says something went wrong.
    nonisolated static func writeLog(_ result: Result<SyncReport, Error>) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/slate-bridge-mac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text: String
        switch result {
        case .success(let r): text = "\(Date())\n\(r)\n"
        case .failure(let e): text = "\(Date())\nfailed: \(e)\n"
        }
        try? text.write(to: dir.appendingPathComponent("last-sync.log"), atomically: true, encoding: .utf8)
    }

    // MARK: - For the menu

    var statusLine: String {
        if syncing { return "Syncing…" }
        guard let lastSync else { return settings.vaultBookmark == nil ? "Not set up" : "Not synced yet" }
        let ago = lastSync.timeIntervalSince(now) > -60
            ? "just now"
            : RelativeDateTimeFormatter().localizedString(for: lastSync, relativeTo: now)
        return "Synced \(ago) · \(events) events · \(contacts) contacts"
    }

    func accountName(_ key: String) -> String {
        settings.folders[key] ?? settings.selection?.names[key] ?? key
    }

    /// "Confirm deletions": the account really did empty, so let its files go.
    func confirmDeletions(_ key: String) {
        let alert = NSAlert()
        alert.messageText = "Delete \(accountName(key))'s files?"
        alert.informativeText = "\(accountName(key)) returned nothing where it had events or contacts before. "
            + "If it really is empty now, its files in the vault can go. If it is only unreachable, cancel and wait."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { syncNow(confirming: [key]) }
    }

    // MARK: - Login item

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }
}
