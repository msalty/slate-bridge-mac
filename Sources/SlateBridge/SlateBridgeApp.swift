import AppKit
import SwiftUI

@main
struct SlateBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.syncing ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                .task { model.start() }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.statusLine)
        Button("Sync Now") { model.syncNow() }
            .keyboardShortcut("s")
            .disabled(model.syncing)
        if !model.problems.isEmpty {
            Divider()
            Text(model.problems.count == 1 ? "1 problem" : "\(model.problems.count) problems")
            ForEach(Array(model.problems.prefix(6).enumerated()), id: \.offset) { _, p in
                Text(p.count > 90 ? String(p.prefix(89)) + "…" : p)
            }
            if model.problems.count > 6 { Text("…and \(model.problems.count - 6) more in the log") }
            Button("Open Sync Log") {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/slate-bridge-mac/last-sync.log"))
            }
        }
        ForEach(model.unconfirmed, id: \.self) { key in
            Button("Confirm Deletions for \(model.accountName(key))…") { model.confirmDeletions(key) }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Slate Bridge") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
