import BridgeCore
import Foundation

/// Both stores, read into one `AccountRead` per account.
///
/// Apple offers no link between a calendar account (`EKSource`) and a
/// contacts account (`CNContainer`), so they are paired by name, which an
/// account usually has the same on both sides (Google, Exchange, iCloud). A
/// pair shares one folder and one `source:` slug.
public final class LiveSources: @unchecked Sendable {
    public let events = EventsSource()
    public let contacts = ContactsSource()

    public init() {}

    /// What to read, by account: the account's key (its `source:` slug) to
    /// the calendar and container ids chosen in it. Kept by account so that
    /// a chosen calendar that has gone fails its own account's read, rather
    /// than dropping out of it and having its meetings taken for cancelled.
    public struct Selection: Codable, Sendable, Equatable {
        public var names: [String: String] = [:]
        public var calendars: [String: Set<String>] = [:]
        public var containers: [String: Set<String>] = [:]

        public init() {}

        public var accounts: [String] { Array(Set(calendars.keys).union(containers.keys)).sorted() }
    }

    public static func key(_ accountName: String) -> String { Labels.slug(accountName) ?? "account" }

    /// Everything but birthdays (the contacts already carry them),
    /// subscribed calendars (holidays and the like, often the same days more
    /// than once over), and a group inside a contacts account (Exchange lists
    /// its contacts folder beside the account, with the same cards).
    public func defaultSelection() -> Selection {
        var s = Selection()
        for c in events.calendars() where !["birthday", "subscription"].contains(c.type) && c.accountType != "birthdays" {
            s.names[Self.key(c.account)] = c.account
            s.calendars[Self.key(c.account), default: []].insert(c.id)
        }
        for c in (try? contacts.containers()) ?? [] where !c.id.hasSuffix(":ABGroup") {
            s.names[Self.key(c.name)] = s.names[Self.key(c.name)] ?? c.name
            s.containers[Self.key(c.name), default: []].insert(c.id)
        }
        return s
    }

    /// Asks for whatever access is still missing; macOS prompts the first time.
    public func requestAccess() async -> (calendars: Bool, contacts: Bool) {
        let cal = (try? await events.requestAccess()) ?? false
        let con = (try? await contacts.requestAccess()) ?? false
        return (cal, con)
    }

    /// One read per chosen account. `folders` renames an account's folder
    /// (settings); its `source:` stays the key.
    public func read(_ selection: Selection, window: DateInterval, folders: [String: String] = [:]) -> [AccountRead] {
        selection.accounts.map { key in
            var problems: [String] = []
            let eventRead: Read<[EventRecord]>
            if let ids = selection.calendars[key], !ids.isEmpty {
                // Calendar order: by title, so the calendar a shared meeting is
                // taken from is the same on every run.
                let present = events.calendars().filter { ids.contains($0.id) }
                if present.count < ids.count {
                    eventRead = .failed("\(ids.count - present.count) chosen calendars are missing")
                } else {
                    let (read, p) = events.read(calendars: present.sorted { ($0.title, $0.id) < ($1.title, $1.id) }.map(\.id), window: window)
                    eventRead = read
                    problems += p
                }
            } else {
                eventRead = .notRead
            }
            let contactRead: Read<[ContactRecord]>
            if let ids = selection.containers[key], !ids.isEmpty {
                var all: [ContactRecord] = []
                var failure: String?
                for id in ids.sorted() {
                    switch contacts.read(container: id) {
                    case .complete(let r): all += r
                    case .failed(let why): failure = why
                    case .notRead: break
                    }
                }
                contactRead = failure.map { .failed($0) } ?? .complete(all)
            } else {
                contactRead = .notRead
            }
            let folder = folders[key] ?? selection.names[key] ?? key
            return AccountRead(source: key, folder: Names.safeSegment(folder), contacts: contactRead,
                               events: eventRead, problems: problems)
        }
    }
}
