import BridgeSources
import BridgeWriter
import Foundation

/// Everything the owner chooses, kept in the app's defaults.
struct AppSettings: Codable, Equatable {
    /// The vault, as a security-scoped bookmark, and where it last was.
    var vaultBookmark: Data?
    var vaultPath: String?
    /// Which calendars and contacts accounts to read. Nil until access is
    /// granted and the defaults can be worked out; explicit from then on.
    var selection: LiveSources.Selection?
    /// Account key → its folder name, where the owner renamed one.
    var folders: [String: String] = [:]
    var attendeeCap = 12
    var monthsBack = 1
    var monthsAhead = 3

    static let key = "settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Getting back into the vault folder chosen once in the open panel.
enum VaultAccess {
    static func bookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            // Outside the sandbox a plain bookmark does the same job.
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    /// The vault's URL now, following it if it moved. A move carries the
    /// manifest to the new path's id, since the id is made from the path:
    /// a vault that moved and lost its manifest would be written again
    /// beside itself.
    static func resolve(_ settings: inout AppSettings) throws -> URL? {
        guard let data = settings.vaultBookmark else { return nil }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        if let old = settings.vaultPath, old != url.path {
            let from = ManifestStore.standard(vault: URL(fileURLWithPath: old, isDirectory: true)).url
            let to = ManifestStore.standard(vault: url).url
            let fm = FileManager.default
            if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) {
                try fm.moveItem(at: from, to: to)
            }
        }
        settings.vaultPath = url.path
        if stale { settings.vaultBookmark = try bookmark(for: url) }
        return url
    }
}
