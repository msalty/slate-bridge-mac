import BridgeCore
import Foundation

/// What the helper last wrote into one vault (§6.2). Kept outside the vault,
/// in the helper's own directory: a file inside it would sync to every device
/// and change on every run.
public struct Manifest: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case event, contact }

    public struct Entry: Codable, Sendable, Equatable {
        public var kind: Kind
        /// Vault-relative, `/`-separated.
        public var path: String
        /// SHA-256 of the bytes last written.
        public var hash: String
        /// The run that last saw the record upstream.
        public var gen: Int
        /// An event's first day, to tell *slid out of the window* from
        /// *cancelled* when it goes.
        public var firstDay: String?
        /// A contact's display name when the file was last named or renamed:
        /// a different one upstream is a rename.
        public var name: String?
        /// A contact's earlier filenames, oldest first: its `aliases:`.
        public var priorNames: [String]?
        /// A contact's addresses, so attendees still link to it on a run
        /// where its account could not be read.
        public var emails: [String]?
        /// Edited by hand: never touched again (§6.2).
        public var released: Bool?

        public init(kind: Kind, path: String, hash: String, gen: Int) {
            self.kind = kind
            self.path = path
            self.hash = hash
            self.gen = gen
        }
    }

    public var version = 1
    /// Bumped once per run.
    public var generation = 0
    /// source slug → uid → entry.
    public var entries: [String: [String: Entry]] = [:]

    public init() {}

    subscript(source: String, uid: String) -> Entry? {
        get { entries[source]?[uid] }
        set { entries[source, default: [:]][uid] = newValue }
    }
}

/// Reads and writes one vault's manifest.
public struct ManifestStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/slate-bridge-mac/<vault id>.json`.
    public static func standard(vaultID: String) -> ManifestStore {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/slate-bridge-mac", isDirectory: true)
        return ManifestStore(url: support.appendingPathComponent("\(vaultID).json"))
    }

    /// A vault the helper has never written into has an empty manifest. A
    /// manifest that cannot be read is an error, never an empty one: an empty
    /// manifest owns nothing, and would have the helper write every file again
    /// beside the ones it already wrote.
    public func load() throws -> Manifest {
        guard FileManager.default.fileExists(atPath: url.path) else { return Manifest() }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    public func save(_ manifest: Manifest) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(manifest).write(to: url, options: .atomic)
    }
}

extension ManifestStore {
    /// One vault's id: the SHA-256 of its real path, so the app and the CLI
    /// pointed at the same folder share one manifest. Two manifests for one
    /// vault would each own nothing the other wrote, and write it all again.
    /// When the app finds its vault moved, it carries the manifest across.
    public static func vaultID(for vault: URL) -> String {
        let real = vault.resolvingSymlinksInPath().standardizedFileURL.path
        return String(Naming.sha256Hex(real).prefix(16))
    }

    public static func standard(vault: URL) -> ManifestStore {
        standard(vaultID: vaultID(for: vault))
    }
}
