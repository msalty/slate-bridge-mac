import BridgeCore
import Foundation

public struct AccountRead: Sendable {
    /// The provider slug, written as `source:`. Fixed for the life of the account.
    public var source: String
    /// The account's folder name under both roots.
    public var folder: String
    public var contacts: Read<[ContactRecord]>
    public var events: Read<[EventRecord]>
    /// What the source noticed while reading: records it skipped, and why.
    public var problems: [String]

    public init(source: String, folder: String, contacts: Read<[ContactRecord]>, events: Read<[EventRecord]>,
                problems: [String] = []) {
        self.source = source
        self.folder = folder
        self.contacts = contacts
        self.events = events
        self.problems = problems
    }
}

public struct SyncOptions: Sendable {
    public var calendarRoot = "backstage/calendar"
    public var contactsRoot = "Contacts/Address Book"
    public var attendeeCap = AttendeeLinking.defaultCap
    /// The window's first day, to report why an event went (§6.3).
    public var windowStart: CivilDate?
    /// Accounts whose empty read the owner has confirmed ("Confirm
    /// deletions"): their deletions go ahead.
    public var confirmedEmpty: Set<String> = []

    public init() {}
}

public struct SyncReport: Sendable, CustomStringConvertible {
    public enum Change: Sendable, Equatable {
        case created(String), updated(String), moved(from: String, to: String), deleted(String, reason: String)
    }

    public var changes: [Change] = []
    public var unchanged = 0
    /// Worth the owner's attention: failed reads, hand edits, duplicates.
    public var problems: [String] = []
    /// Live files by kind after the run.
    public var events = 0
    public var contacts = 0

    public var description: String {
        var lines = changes.map { c -> String in
            switch c {
            case .created(let p): "created  \(p)"
            case .updated(let p): "updated  \(p)"
            case .moved(let a, let b): "moved    \(a) → \(b)"
            case .deleted(let p, let why): "deleted  \(p) (\(why))"
            }
        }
        lines += problems.map { "problem  \($0)" }
        lines.append("\(events) events · \(contacts) contacts · \(changes.count) changed · \(unchanged) unchanged")
        return lines.joined(separator: "\n")
    }
}

/// One run: contacts, then events, into one vault (§6.2, §6.4, §6.5).
public final class Sync {
    let vault: Vault
    var manifest: Manifest
    let options: SyncOptions
    var report = SyncReport()
    let gen: Int

    /// Lowercased stem → how many notes outside `backstage/` answer to it:
    /// the names a link can reach. Kept current as files are written.
    var stems: [String: Int] = [:]
    /// (source, uid) → the paths carrying them, outside the trash. Built only
    /// when a file is not where the manifest says (§6.2).
    var owners: [String: [String]]?

    public static func run(vault root: URL, store: ManifestStore, accounts: [AccountRead],
                           options: SyncOptions = SyncOptions()) throws -> SyncReport {
        let sync = Sync(vault: Vault(root: root), manifest: try store.load(), options: options)
        try sync.run(accounts)
        try store.save(sync.manifest)
        return sync.report
    }

    init(vault: Vault, manifest: Manifest, options: SyncOptions) {
        self.vault = vault
        self.manifest = manifest
        self.options = options
        self.gen = manifest.generation + 1
    }

    func run(_ accounts: [AccountRead]) throws {
        for a in accounts { report.problems += a.problems.map { "\(a.folder): \($0)" } }
        for path in vault.allFiles() where Vault.isNote(path) && !Vault.isBackstage(path) {
            stems[Vault.stem(path).lowercased(), default: 0] += 1
        }
        // Contacts first: attendee links read their current names (§6.4).
        // A card is projected once: Exchange shows its contacts folder as a
        // container of its own beside the account, holding the same cards,
        // so a card an earlier account already gave is skipped.
        var given: [String: String] = [:]
        for a in accounts {
            guard let contacts = records(a.contacts, a, kind: .contact) else { continue }
            var skipped: [String: Int] = [:]
            for c in contacts.sorted(by: { ($0.name, $0.uid) < ($1.name, $1.uid) }) {
                if let earlier = given[c.uid] {
                    skipped[earlier, default: 0] += 1
                    continue
                }
                given[c.uid] = a.folder
                try contact(c, a)
            }
            for (earlier, n) in skipped.sorted(by: { $0.key < $1.key }) {
                report.problems.append("\(a.folder): \(n) contacts are the same cards as \(earlier)'s; skipped")
            }
        }
        for a in accounts { try deletions(a, kind: .contact, read: a.contacts.isComplete, empty: a.contacts.isEmpty) }

        let directory = contactDirectory()
        for a in accounts {
            if let events = records(a.events, a, kind: .event) {
                for e in events.sorted(by: { ($0.timing.firstDay, $0.uid) < ($1.timing.firstDay, $1.uid) }) {
                    try event(e, a, directory)
                }
            }
        }
        for a in accounts { try deletions(a, kind: .event, read: a.events.isComplete, empty: a.events.isEmpty) }

        manifest.generation = gen
        for (_, byUID) in manifest.entries {
            for (_, e) in byUID where e.released != true {
                if e.kind == .event { report.events += 1 } else { report.contacts += 1 }
            }
        }
    }

    /// The records of a complete read, less any whose uid is missing or
    /// repeated — reported, never guessed at. A repeated uid still counts as
    /// seen, so its file is not taken for cancelled.
    func records<R: Identified>(_ read: Read<[R]>, _ a: AccountRead, kind: Manifest.Kind) -> [R]? {
        switch read {
        case .notRead: return nil
        case .failed(let why):
            report.problems.append("\(a.folder): \(kind == .event ? "calendars" : "contacts") not read (\(why)); nothing deleted")
            return nil
        case .complete(let all):
            var count: [String: Int] = [:]
            for r in all { count[r.uid, default: 0] += 1 }
            for (uid, n) in count where n > 1 {
                report.problems.append("\(a.folder): \(n) records share the uid \(uid); skipped")
                manifest[a.source, uid]?.gen = gen
            }
            if count[""] != nil { report.problems.append("\(a.folder): a record with no uid; skipped") }
            return all.filter { !$0.uid.isEmpty && count[$0.uid] == 1 }
        }
    }

    // MARK: - Finding a file (§6.2)

    enum Located {
        /// Ours, unedited, at this path.
        case ours(String)
        /// Ours, but not the bytes last written: edited by hand.
        case edited(String)
        /// More than one file claims the uid and none is unedited.
        case ambiguous
        /// Deleted, detached, or only in the trash.
        case gone
    }

    func locate(_ source: String, _ uid: String, _ entry: Manifest.Entry) -> Located {
        if let data = vault.read(entry.path), Ownership(data) == Ownership(source: source, uid: uid) {
            return Naming.sha256Hex(data) == entry.hash ? .ours(entry.path) : .edited(entry.path)
        }
        // Not where it was left: look for it by uid, anywhere but the trash.
        let owner = Ownership(source: source, uid: uid)
        let found = (ownersIndex()[key(source, uid)] ?? []).filter { vault.read($0).flatMap(Ownership.init) == owner }
        guard !found.isEmpty else { return .gone }
        let matching = found.filter { vault.hash($0) == entry.hash }
        if let record = matching.first {
            for other in found where other != record {
                report.problems.append("\(other) also claims uid \(uid); left alone")
            }
            return .ours(record)
        }
        if found.count == 1 { return .edited(found[0]) }
        for p in found { report.problems.append("\(p) claims uid \(uid), edited; left alone") }
        return .ambiguous
    }

    /// `locate`, except that a file edited by hand stays released for good,
    /// even if its bytes are later put back (§6.2).
    func locateEntry(_ source: String, _ uid: String, _ entry: Manifest.Entry) -> Located {
        let found = locate(source, uid, entry)
        if entry.released == true, case .ours(let path) = found { return .edited(path) }
        return found
    }

    func ownersIndex() -> [String: [String]] {
        if let owners { return owners }
        var index: [String: [String]] = [:]
        for path in vault.allFiles() where Vault.isNote(path) && !Vault.isTrash(path) {
            if let data = vault.read(path), let o = Ownership(data) {
                index[key(o.source, o.uid), default: []].append(path)
            }
        }
        owners = index
        return index
    }

    func key(_ source: String, _ uid: String) -> String { "\(source)\u{0}\(uid)" }

    // MARK: - Contacts

    func contact(_ c: ContactRecord, _ a: AccountRead) throws {
        let emails = c.emails.map(\.value)
        guard var entry = manifest[a.source, c.uid] else {
            return try createContact(c, a, priorNames: [])
        }
        entry.gen = gen
        entry.emails = emails
        switch locateEntry(a.source, c.uid, entry) {
        case .gone:
            // Deleted or detached, and still upstream: written afresh (§6.2).
            return try createContact(c, a, priorNames: entry.priorNames ?? [])
        case .ambiguous:
            entry.released = true
        case .edited(let path):
            if entry.released != true { report.problems.append("\(path) was edited by hand; no longer updated") }
            entry.path = path
            entry.released = true
        case .ours(var path):
            if path != entry.path { report.changes.append(.moved(from: entry.path, to: path)) }
            // Renamed upstream: the file follows, while it is still where and
            // what the helper named it (§2.2). One you moved or renamed stays.
            if c.name != entry.name, path == entry.path {
                let stem = Vault.stem(path)
                let dir = (path as NSString).deletingLastPathComponent
                let name = Naming.contactName(name: c.name, org: c.org, emails: emails) { candidate in
                    candidate.lowercased() != stem.lowercased() && self.taken(candidate)
                }
                if name.lowercased() != stem.lowercased() {
                    let to = "\(dir)/\(name).md"
                    try vault.move(path, to: to)
                    report.changes.append(.moved(from: path, to: to))
                    forget(path)
                    remember(to)
                    var prior = entry.priorNames ?? []
                    if !prior.contains(where: { $0.lowercased() == stem.lowercased() }) { prior.append(stem) }
                    entry.priorNames = prior
                    path = to
                }
            }
            entry.name = c.name
            entry.path = path
            let text = ContactFile.render(c, source: a.source, aliases: aliases(entry.priorNames, path))
            entry.hash = try put(text, path, created: false)
        }
        manifest[a.source, c.uid] = entry
    }

    func createContact(_ c: ContactRecord, _ a: AccountRead, priorNames: [String]) throws {
        let name = Naming.contactName(name: c.name, org: c.org, emails: c.emails.map(\.value), taken: taken)
        let path = "\(options.contactsRoot)/\(Names.safeSegment(a.folder))/\(name).md"
        let text = ContactFile.render(c, source: a.source, aliases: aliases(priorNames, path))
        var entry = Manifest.Entry(kind: .contact, path: path, hash: try put(text, path, created: true), gen: gen)
        entry.name = c.name
        entry.emails = c.emails.map(\.value)
        entry.priorNames = priorNames.isEmpty ? nil : priorNames
        remember(path)
        manifest[a.source, c.uid] = entry
    }

    /// Earlier names, less the one the file has now.
    func aliases(_ prior: [String]?, _ path: String) -> [String] {
        let stem = Vault.stem(path).lowercased()
        return (prior ?? []).filter { $0.lowercased() != stem }
    }

    /// Whether any note outside `backstage/` already answers to `name`.
    func taken(_ name: String) -> Bool { stems[name.lowercased(), default: 0] > 0 }

    func remember(_ path: String) {
        if !Vault.isBackstage(path) { stems[Vault.stem(path).lowercased(), default: 0] += 1 }
    }

    func forget(_ path: String) {
        let s = Vault.stem(path).lowercased()
        if !Vault.isBackstage(path), let n = stems[s] { stems[s] = n > 1 ? n - 1 : nil }
    }

    /// Every projected contact where it is now, for attendee links — those of
    /// accounts that could not be read this time included.
    func contactDirectory() -> ContactDirectory {
        var entries: [ContactDirectory.Entry] = []
        for (_, byUID) in manifest.entries {
            for (_, e) in byUID where e.kind == .contact && vault.exists(e.path) {
                let stem = Vault.stem(e.path)
                entries.append(.init(
                    emails: e.emails ?? [], stem: stem,
                    pathStem: String(e.path.dropLast((e.path as NSString).pathExtension.count + 1)),
                    shared: stems[stem.lowercased(), default: 0] > 1))
            }
        }
        return ContactDirectory(entries)
    }

    // MARK: - Events

    func event(_ e: EventRecord, _ a: AccountRead, _ directory: ContactDirectory) throws {
        let attendees = AttendeeLinking.items(e.attendees, directory: directory, cap: options.attendeeCap)
        let text = EventFile.render(e, source: a.source, attendees: attendees)
        guard var entry = manifest[a.source, e.uid] else { return try createEvent(e, a, text) }
        entry.gen = gen
        entry.firstDay = e.timing.firstDay.description
        switch locateEntry(a.source, e.uid, entry) {
        case .gone:
            return try createEvent(e, a, text)
        case .ambiguous:
            entry.released = true
        case .edited(let path):
            if entry.released != true { report.problems.append("\(path) was edited by hand; no longer updated") }
            entry.path = path
            entry.released = true
        case .ours(let path):
            // The name is the file's for the life of the record: a new title
            // upstream changes `title:` and nothing else (§2.1).
            if path != entry.path { report.changes.append(.moved(from: entry.path, to: path)) }
            entry.path = path
            entry.hash = try put(text, path, created: false)
        }
        manifest[a.source, e.uid] = entry
    }

    func createEvent(_ e: EventRecord, _ a: AccountRead, _ text: String) throws {
        let day = e.timing.firstDay
        let dir = "\(options.calendarRoot)/\(Names.safeSegment(a.folder))/\(day.year)/\(String(format: "%02d", day.month))"
        let names = vault.namesIn(dir)
        let name = Naming.eventName(title: EventFile.displayTitle(e.title), uid: e.uid) {
            names.contains("\($0).md".lowercased())
        }
        let path = "\(dir)/\(name).md"
        var entry = Manifest.Entry(kind: .event, path: path, hash: try put(text, path, created: true), gen: gen)
        entry.firstDay = day.description
        manifest[a.source, e.uid] = entry
    }

    // MARK: - Writing and deleting

    /// Writes when the bytes differ; returns the hash of what is there now.
    func put(_ text: String, _ path: String, created: Bool) throws -> String {
        // A new name is chosen clear of every file there; this is the last
        // guard against writing over one the helper does not own.
        if created, vault.exists(path) { throw SyncError.occupied(path) }
        if try vault.write(text, to: path) {
            report.changes.append(created ? .created(path) : .updated(path))
        } else {
            report.unchanged += 1
        }
        return Naming.sha256Hex(Data(text.utf8))
    }

    /// Records gone from a complete read: cancelled or deleted upstream, or
    /// slid out of the window. Both are found the same way — by generation,
    /// an entry this run did not see — and both only on a complete read
    /// (§6.2).
    func deletions(_ a: AccountRead, kind: Manifest.Kind, read complete: Bool, empty: Bool) throws {
        guard complete, let byUID = manifest.entries[a.source] else { return }
        let stale = byUID.filter { $0.value.kind == kind && $0.value.gen < gen }.sorted { $0.key < $1.key }
        guard !stale.isEmpty else { return }
        let live = byUID.contains { $0.value.kind == kind && $0.value.released != true }
        if empty, live, !options.confirmedEmpty.contains(a.source) {
            report.problems.append("\(a.folder): no \(kind == .event ? "events" : "contacts") came back; "
                + "nothing deleted until confirmed")
            return
        }
        for (uid, entry) in stale {
            manifest.entries[a.source]?[uid] = nil
            guard entry.released != true else { continue }
            switch locate(a.source, uid, entry) {
            case .ours(let path):
                try vault.delete(path)
                forget(path)
                report.changes.append(.deleted(path, reason: reason(kind, entry)))
                if kind == .event {
                    let root = "\(options.calendarRoot)/\(Names.safeSegment(a.folder))"
                    vault.pruneEmpty((path as NSString).deletingLastPathComponent, stop: root)
                }
            case .edited(let path):
                report.problems.append("\(path) is gone upstream but was edited by hand; left alone")
            case .ambiguous, .gone:
                break
            }
        }
    }

    func reason(_ kind: Manifest.Kind, _ entry: Manifest.Entry) -> String {
        guard kind == .event else { return "deleted upstream" }
        if let start = options.windowStart, let day = entry.firstDay.flatMap(CivilDate.init(string:)), day < start {
            return "slid out of the window"
        }
        return "cancelled upstream"
    }
}

public enum SyncError: Error, CustomStringConvertible {
    case occupied(String)

    public var description: String {
        switch self {
        case .occupied(let p): "refusing to write over \(p), which the helper does not own"
        }
    }
}

/// A record with a uid.
protocol Identified { var uid: String { get } }
extension EventRecord: Identified {}
extension ContactRecord: Identified {}

extension AccountRead {
    /// The reads a `RecordSet` stands for: an account marked `failed` failed
    /// both reads; a kind left out was not read.
    public static func from(_ set: RecordSet) -> [AccountRead] {
        set.accounts.map { a in
            if let why = a.failed {
                return AccountRead(source: a.source, folder: a.folder, contacts: .failed(why), events: .failed(why))
            }
            return AccountRead(
                source: a.source, folder: a.folder,
                contacts: a.contacts.map { .complete($0) } ?? .notRead,
                events: a.events.map { .complete($0) } ?? .notRead)
        }
    }
}
