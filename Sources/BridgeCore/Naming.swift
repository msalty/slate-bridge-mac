import CryptoKit
import Foundation

/// Choosing a name for a file the helper is about to write for the first time.
/// A name, once given, is never chosen again: the writer keeps it (§2.1).
public enum Naming {
    /// Lowercase hex SHA-256 of the UTF-8 bytes.
    public static func sha256Hex(_ data: some DataProtocol) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ s: String) -> String { sha256Hex(Data(s.utf8)) }

    /// A meeting: `<title> (<tag>)`, the tag the first four hex digits of
    /// SHA-256(uid), lengthened a digit at a time, up to eight, while the name
    /// is taken in the folder (§2.1). `taken` compares ignoring case, as the
    /// file system does. Past eight — two uids agreeing on 32 bits and a title
    /// — a counter goes on the end, in the shape Slate reads back.
    public static func eventName(title: String, uid: String, taken: (String) -> Bool) -> String {
        let hex = sha256Hex(uid)
        for n in 4...8 {
            let name = Names.importedNoteName(title, tag: String(hex.prefix(n)))
            if !taken(name) { return name }
        }
        let full = Names.importedNoteName(title, tag: String(hex.prefix(8)))
        var k = 2
        while taken("\(full) \(k)") { k += 1 }
        return "\(full) \(k)"
    }

    /// A contact: its display name, which is what `[[Jane Doe]]` links to.
    /// When any note in the vault already answers to that name, it takes the
    /// org, then the local part of an email, in brackets —
    /// `Jane Doe (Example Corp)` — and then a counter (§2.2).
    public static func contactName(
        name: String, org: String?, emails: [String], taken: (String) -> Bool
    ) -> String {
        let base = Names.safeSegment(name)
        var tries = [base]
        if let org = nonEmpty(org) { tries.append(Names.bracketed(name, org)) }
        for email in emails {
            if let local = email.split(separator: "@").first.flatMap({ nonEmpty(String($0)) }) {
                tries.append(Names.bracketed(name, local))
            }
        }
        for name in tries where !taken(name) { return name }
        var k = 2
        while taken(Names.numberedSegment(base, k)) { k += 1 }
        return Names.numberedSegment(base, k)
    }
}
