import BridgeCore
@testable import BridgeWriter
import Foundation

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

/// The example vault's files that are the user's: never the helper's to touch.
let userFiles = [
    "Calendar/2026/09/Design review - 2026-09-21.md",
    "Calendar/2026/09/Standup - 2026-09-22.md",
    "Contacts/Notes on Jane Doe.md",
]

/// A scratch vault and manifest in a temporary folder, and the fixture
/// records to sync into it.
final class Harness {
    let dir: URL
    let vault: URL
    let store: ManifestStore
    var records: RecordSet
    var options = SyncOptions()

    init(seedUserFiles: Bool = true, seedPriorNames: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("slate-bridge-\(UUID().uuidString)")
        vault = dir.appendingPathComponent("vault")
        store = ManifestStore(url: dir.appendingPathComponent("state/manifest.json"))
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        records = try JSONDecoder().decode(RecordSet.self, from: Data(contentsOf: fixtures.appendingPathComponent("records.json")))
        if seedUserFiles {
            for f in userFiles { try write(f, try String(contentsOf: fixtures.appendingPathComponent("vault/\(f)"), encoding: .utf8)) }
        }
        if seedPriorNames {
            // What the manifest would remember from Jane's earlier names:
            // an entry whose file has gone, carrying its prior names.
            var m = Manifest()
            var e = Manifest.Entry(kind: .contact, path: "Contacts/Address Book/Fastmail/JD.md", hash: "", gen: 0)
            e.name = "JD"
            e.priorNames = ["Jane Smith", "JD"]
            m.entries["fastmail"] = ["jane-doe@fastmail.com": e]
            try store.save(m)
        }
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    func sync(_ accounts: [AccountRead]? = nil) throws -> SyncReport {
        try Sync.run(vault: vault, store: store, accounts: accounts ?? AccountRead.from(records), options: options)
    }

    func manifest() throws -> Manifest { try store.load() }

    // MARK: Files

    func url(_ path: String) -> URL { vault.appendingPathComponent(path) }

    func read(_ path: String) -> String? { try? String(contentsOf: url(path), encoding: .utf8) }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }

    func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url(path), atomically: true, encoding: .utf8)
    }

    func move(_ from: String, _ to: String) throws {
        try FileManager.default.createDirectory(at: url(to).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url(from), to: url(to))
    }

    /// Every file in the vault, path → contents.
    func tree() -> [String: String] {
        var out: [String: String] = [:]
        let e = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil)!
        let base = vault.standardizedFileURL.path + "/"
        for case let u as URL in e where !u.hasDirectoryPath {
            let p = String(u.standardizedFileURL.path.dropFirst(base.count))
            out[p] = try? String(contentsOf: u, encoding: .utf8)
        }
        return out
    }

    func mtime(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(path).path))?[.modificationDate] as? Date
    }

    /// Sets every file's mtime far in the past, so any touch shows.
    func ageAllFiles() throws {
        for p in tree().keys {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: url(p).path)
        }
    }

    // MARK: Records

    func editEvent(_ uid: String, _ change: (inout EventRecord) -> Void) {
        for i in records.accounts.indices {
            if let j = records.accounts[i].events?.firstIndex(where: { $0.uid == uid }) {
                change(&records.accounts[i].events![j])
            }
        }
    }

    func removeEvent(_ uid: String) {
        for i in records.accounts.indices { records.accounts[i].events?.removeAll { $0.uid == uid } }
    }

    func editContact(_ uid: String, _ change: (inout ContactRecord) -> Void) {
        for i in records.accounts.indices {
            if let j = records.accounts[i].contacts?.firstIndex(where: { $0.uid == uid }) {
                change(&records.accounts[i].contacts![j])
            }
        }
    }
}

let designReview = "backstage/calendar/Fastmail/2026/09/Design review (b361).md"
let officeClosed = "backstage/calendar/Fastmail/2026/09/Office closed (3a77).md"
let tokyoSync = "backstage/calendar/Work/2026/10/Tokyo sync (43ce).md"
let janeFastmail = "Contacts/Address Book/Fastmail/Jane Doe.md"
let janeWork = "Contacts/Address Book/Work/Jane Doe (Example Corp).md"
