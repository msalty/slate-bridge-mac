import Foundation

/// Attendee linking (§6.4).
public struct ContactDirectory: Sendable {
    /// One projected contact, where it is now.
    public struct Entry: Sendable {
        public var emails: [String]
        /// The filename without `.md`: what a link names.
        public var stem: String
        /// The vault path without `.md`: what a link names when the stem is shared.
        public var pathStem: String
        /// Whether another note in the vault answers to the same name.
        public var shared: Bool

        public init(emails: [String], stem: String, pathStem: String, shared: Bool) {
            self.emails = emails
            self.stem = stem
            self.pathStem = pathStem
            self.shared = shared
        }
    }

    private var byEmail: [String: Entry] = [:]

    /// Where two contacts carry one address, the one first by path wins, so
    /// the choice is the same on every run.
    public init(_ entries: [Entry]) {
        for e in entries.sorted(by: { $0.pathStem < $1.pathStem }) {
            for email in e.emails {
                let key = Self.key(email)
                if !key.isEmpty, byEmail[key] == nil { byEmail[key] = e }
            }
        }
    }

    /// Exact match on the address; only its case is ignored.
    public func link(forEmail email: String) -> String? {
        guard let e = byEmail[Self.key(email)] else { return nil }
        return "[[\(e.shared ? e.pathStem : e.stem)]]"
    }

    static func key(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum AttendeeLinking {
    public static let defaultCap = 12

    /// The `attendees:` items, or nil for no key. Yourself left out; a matched
    /// contact as a link to its current name; anyone else as plain text, never
    /// a link that resolves to nothing; no list at all above `cap`.
    public static func items(_ attendees: [Attendee], directory: ContactDirectory, cap: Int) -> [String]? {
        let others = attendees.filter { !$0.isCurrentUser }
        guard !others.isEmpty, others.count <= cap else { return nil }
        var out: [String] = []
        for a in others {
            let item: String?
            if let email = nonEmpty(a.email), let link = directory.link(forEmail: email) {
                item = link
            } else {
                item = nonEmpty(a.name).map(oneLineText) ?? nonEmpty(a.email)
            }
            if let item, !out.contains(item) { out.append(item) }
        }
        return out.isEmpty ? nil : out
    }
}
