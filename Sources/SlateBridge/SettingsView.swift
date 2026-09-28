import AppKit
import BridgeSources
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralPane(model: model).tabItem { Label("General", systemImage: "gearshape") }
            AccountsPane(model: model).tabItem { Label("Accounts", systemImage: "person.2") }
        }
        .frame(width: 520, height: 480)
        .onAppear {
            // A menu-bar app's windows otherwise open behind everything.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text(model.settings.vaultPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None chosen")
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(model.settings.vaultPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…", action: chooseVault)
                }
                Text("Meetings go in backstage/calendar/, contacts in Contacts/Address Book/. Nothing else in the vault is touched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Window") {
                Stepper("\(model.settings.monthsBack) month\(model.settings.monthsBack == 1 ? "" : "s") back",
                        value: $model.settings.monthsBack, in: 0...12)
                Stepper("\(model.settings.monthsAhead) months ahead", value: $model.settings.monthsAhead, in: 1...24)
            }
            Section("Attendees") {
                Stepper("No list above \(model.settings.attendeeCap) people",
                        value: $model.settings.attendeeCap, in: 0...100)
            }
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.opensAtLogin },
                    set: { on in
                        do { try model.setOpensAtLogin(on); loginError = nil } catch { loginError = error.localizedDescription }
                    }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { model.syncSoon(after: 3) }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Vault"
        panel.message = "Choose your Slate vault folder."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? VaultAccess.bookmark(for: url) else { return }
        model.settings.vaultBookmark = bookmark
        model.settings.vaultPath = url.path
    }
}

struct AccountsPane: View {
    @ObservedObject var model: AppModel
    @State private var calendars: [EventsSource.Calendar] = []
    @State private var containers: [ContactsSource.Container] = []

    var accounts: [String] {
        let names = calendars.map(\.account) + containers.map(\.name)
        return Array(Set(names.map(LiveSources.key))).sorted()
    }

    var body: some View {
        Form {
            if model.settings.selection == nil {
                Text("Waiting for access to Calendars and Contacts. Allow Slate Bridge in System Settings → Privacy & Security.")
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts, id: \.self) { key in
                Section {
                    TextField("Folder", text: folderBinding(key), prompt: Text(defaultName(key)))
                    ForEach(calendars.filter { LiveSources.key($0.account) == key }, id: \.id) { c in
                        Toggle(isOn: calendarBinding(key, c)) {
                            Text(c.title) + Text(kind(c)).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(containers.filter { LiveSources.key($0.name) == key }, id: \.id) { c in
                        Toggle(isOn: containerBinding(key, c)) {
                            Text("Contacts") + Text(c.id.hasSuffix(":ABGroup") ? " (a folder of the account: the same cards)" : "")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(defaultName(key))
                } footer: {
                    Text("source: \(key)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onChange(of: model.settings) { model.syncSoon(after: 3) }
    }

    func reload() {
        calendars = model.sources.events.calendars().sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        containers = (try? model.sources.contacts.containers()) ?? []
    }

    func defaultName(_ key: String) -> String {
        calendars.first { LiveSources.key($0.account) == key }?.account
            ?? containers.first { LiveSources.key($0.name) == key }?.name ?? key
    }

    func kind(_ c: EventsSource.Calendar) -> String {
        switch c.type {
        case "birthday": " (birthdays)"
        case "subscription": " (subscribed)"
        default: ""
        }
    }

    func folderBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { model.settings.folders[key] ?? "" },
            set: { model.settings.folders[key] = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    func calendarBinding(_ key: String, _ c: EventsSource.Calendar) -> Binding<Bool> {
        Binding(
            get: { model.settings.selection?.calendars[key]?.contains(c.id) ?? false },
            set: { on in
                var s = model.settings.selection ?? LiveSources.Selection()
                s.names[key] = c.account
                if on { s.calendars[key, default: []].insert(c.id) } else { s.calendars[key, default: []].remove(c.id) }
                model.settings.selection = s
            })
    }

    func containerBinding(_ key: String, _ c: ContactsSource.Container) -> Binding<Bool> {
        Binding(
            get: { model.settings.selection?.containers[key]?.contains(c.id) ?? false },
            set: { on in
                var s = model.settings.selection ?? LiveSources.Selection()
                s.names[key] = s.names[key] ?? c.name
                if on { s.containers[key, default: []].insert(c.id) } else { s.containers[key, default: []].remove(c.id) }
                model.settings.selection = s
            })
    }
}
