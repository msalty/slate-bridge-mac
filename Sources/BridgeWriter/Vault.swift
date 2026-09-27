import BridgeCore
import Foundation

/// A vault folder on disk: reading, writing and finding files. Paths are
/// vault-relative and `/`-separated throughout.
final class Vault {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) { self.root = root.standardizedFileURL }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    func exists(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: url(path).path, isDirectory: &dir) && !dir.boolValue
    }

    func read(_ path: String) -> Data? { try? Data(contentsOf: url(path)) }

    func hash(_ path: String) -> String? { read(path).map(Naming.sha256Hex) }

    /// Writes `text` unless the file already holds exactly those bytes, in
    /// which case nothing is touched, not even the mtime (§6.5). Atomic: a
    /// temporary file beside it, then a rename over it. True when it wrote.
    @discardableResult
    func write(_ text: String, to path: String) throws -> Bool {
        let data = Data(text.utf8)
        if read(path) == data { return false }
        let target = url(path)
        let dir = target.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".\(UUID().uuidString).slate-bridge.tmp")
        try data.write(to: temp)
        if Foundation.rename(temp.path, target.path) != 0 {
            let err = errno
            try? fm.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }
        return true
    }

    func move(_ from: String, to: String) throws {
        try fm.createDirectory(at: url(to).deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: url(from), to: url(to))
    }

    func delete(_ path: String) throws { try fm.removeItem(at: url(path)) }

    /// Removes `dir` and then its parents while they are empty, stopping at
    /// `stop` — the account folder a meeting's month folder sits in.
    func pruneEmpty(_ dir: String, stop: String) {
        var d = dir
        while d.count > stop.count, d.hasPrefix(stop + "/") {
            guard let items = try? fm.contentsOfDirectory(atPath: url(d).path),
                  items.allSatisfy({ $0 == ".DS_Store" }) else { return }
            try? fm.removeItem(at: url(d))
            d = (d as NSString).deletingLastPathComponent
        }
    }

    /// The filenames in a folder, lowercased: what a new name must not be.
    func namesIn(_ dir: String) -> Set<String> {
        Set(((try? fm.contentsOfDirectory(atPath: url(dir).path)) ?? []).map { $0.lowercased() })
    }

    /// Every file under the vault, skipping hidden files and folders.
    func allFiles() -> [String] {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let u as URL in e {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let p = u.standardizedFileURL.path
            if p.hasPrefix(base) { out.append(String(p.dropFirst(base.count))) }
        }
        return out.sorted()
    }

    static func isNote(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "txt"
    }

    static func stem(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func isBackstage(_ path: String) -> Bool { path.lowercased().hasPrefix("backstage/") }
    static func isTrash(_ path: String) -> Bool { path.lowercased().hasPrefix("backstage/trash/") }
}

/// The two frontmatter keys that say who owns a file (§2.3), read the way
/// Slate's `parseFrontmatter` and `externalSource` read them.
struct Ownership: Equatable {
    var source: String
    var uid: String

    init(source: String, uid: String) {
        self.source = source
        self.uid = uid
    }

    /// Nil unless the file has a frontmatter block with both keys.
    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("---") else { return nil }
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var source: String?
        var uid: String?
        for line in lines.dropFirst() {
            if line.hasPrefix("---"), line.dropFirst(3).allSatisfy({ $0 == " " || $0 == "\t" }) { break }
            // `^([A-Za-z0-9_.-]+)\s*:\s*(.*)$`: the key starts the line.
            guard let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let key = head.hasSuffix(" ") || head.hasSuffix("\t")
                ? String(head.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()) : String(head)
            guard key == "source" || key == "uid" else { continue }
            let value = Self.unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            if key == "source" { source = value } else { uid = value }
        }
        guard let s = source?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
              let u = uid?.trimmingCharacters(in: .whitespaces), !u.isEmpty else { return nil }
        self.source = s
        self.uid = u
    }

    /// Slate's `unquote`: a double-quoted value is JSON, a single-quoted one
    /// YAML's, anything else as written. A list (`[a, b]`) names nobody.
    static func unquote(_ s: String) -> String? {
        if s.hasPrefix("["), s.hasSuffix("]") { return nil }
        if s == "true" || s == "false" { return nil }
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            if let v = try? JSONDecoder().decode(String.self, from: Data(s.utf8)) { return v }
            return String(s.dropFirst().dropLast())
        }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }
}
