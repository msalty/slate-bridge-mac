import BridgeCore
import BridgeSources
import BridgeWriter
import Foundation

let usage = """
    usage: slate-bridge sync --vault DIR --records FILE [options]
           slate-bridge dump contacts [--summary | --container ID]

    sync runs one sync into DIR from records in FILE (the format of
    Tests/Fixtures/records.json): the whole pipeline, no permissions needed.

      --state FILE          the manifest (default: ~/Library/Application
                            Support/slate-bridge-mac/<vault id>.json)
      --window-start DAY    the window's first day, YYYY-MM-DD, to tell an
                            event that slid out of the window from a cancelled one
      --attendee-cap N      no attendee list above N (default 12)
      --confirm SOURCE      delete for SOURCE even though its read came back
                            empty (repeatable)

    dump contacts prints every contacts account (container) as JSON, or with
    --container ID the records that account would project. It reads the real
    address book, so macOS asks for Contacts access the first time.
    --summary prints counts only, per container: no names, numbers or
    addresses.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("slate-bridge: \(message)\n".utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())

func printJSON<T: Encodable>(_ value: T) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try enc.encode(value), as: UTF8.self))
}

/// Per container: how many cards, which labels, and how far containers
/// overlap — by uid, and by email address, which is what attendee linking
/// and name clashes turn on. Counts only; nothing that identifies anyone.
struct ContainerSummary: Encodable {
    var name: String
    var type: String
    var id: String
    var read: String
    var cards = 0
    var withEmail = 0
    var uidsAlsoInAnotherContainer = 0
    var emailsAlsoInAnotherContainer = 0
    var namesRepeatedInThisContainer = 0
    var labels: [String: [String: Int]] = [:]
}

func contactsSummary(_ source: ContactsSource) throws -> [ContainerSummary] {
    var reads: [(ContactsSource.Container, Read<[ContactRecord]>)] = []
    for c in try source.containers() { reads.append((c, source.read(container: c.id))) }
    func records(_ r: Read<[ContactRecord]>) -> [ContactRecord] {
        if case .complete(let x) = r { x } else { [] }
    }
    var uidCount: [String: Int] = [:]
    var emailCount: [String: Int] = [:]
    for (_, r) in reads {
        for uid in Set(records(r).map(\.uid)) { uidCount[uid, default: 0] += 1 }
        for e in Set(records(r).flatMap { $0.emails.map { $0.value.lowercased() } }) { emailCount[e, default: 0] += 1 }
    }
    return reads.map { c, r in
        var s = ContainerSummary(name: c.name, type: c.type, id: c.id, read: {
            switch r { case .complete: "complete"; case .failed(let why): "failed: \(why)"; case .notRead: "not read" }
        }())
        let all = records(r)
        s.cards = all.count
        s.withEmail = all.filter { !$0.emails.isEmpty }.count
        s.uidsAlsoInAnotherContainer = all.filter { uidCount[$0.uid, default: 0] > 1 }.count
        s.emailsAlsoInAnotherContainer = Set(all.flatMap { $0.emails.map { $0.value.lowercased() } })
            .filter { emailCount[$0, default: 0] > 1 }.count
        var names: [String: Int] = [:]
        for x in all { names[x.name.lowercased(), default: 0] += 1 }
        s.namesRepeatedInThisContainer = names.values.filter { $0 > 1 }.reduce(0, +)
        func tally(_ kind: String, _ labels: [String?]) {
            for l in labels { s.labels[kind, default: [:]][l ?? "(none)", default: 0] += 1 }
        }
        tally("phone", all.flatMap { $0.phones.map(\.label) })
        tally("email", all.flatMap { $0.emails.map(\.label) })
        tally("address", all.flatMap { $0.addresses.map(\.label) })
        tally("url", all.flatMap { $0.urls.map(\.label) })
        tally("date", all.flatMap { $0.dates.map(\.label) })
        tally("related", all.flatMap { $0.related.map(\.label) })
        tally("social", all.flatMap { $0.social.map(\.label) })
        tally("im", all.flatMap { $0.im.map(\.label) })
        tally("birthday", all.map { $0.birthday == nil ? nil : ($0.birthday!.year == nil ? "no year" : "with year") }.filter { $0 != nil })
        return s
    }
}

if args.first == "dump" {
    guard args.count >= 2, args[1] == "contacts" else { fail("dump what? contacts\n\n\(usage)") }
    let source = ContactsSource()
    do {
        guard try await source.requestAccess() else { fail("Contacts access was not granted") }
        if args.count == 3, args[2] == "--summary" {
            try printJSON(try contactsSummary(source))
        } else if args.count == 4, args[2] == "--container" {
            switch source.read(container: args[3]) {
            case .complete(let records): try printJSON(records)
            case .failed(let why): fail(why)
            case .notRead: fail("not read")
            }
        } else if args.count == 2 {
            try printJSON(try source.containers())
        } else {
            fail(usage)
        }
    } catch {
        fail("\(error)")
    }
    exit(0)
}

guard args.first == "sync" else { fail(args.isEmpty ? usage : "unknown command \(args[0])\n\n\(usage)") }
args.removeFirst()

var vault: URL?
var recordsFile: URL?
var state: URL?
var options = SyncOptions()
while !args.isEmpty {
    let flag = args.removeFirst()
    guard let value = args.first else { fail("\(flag) needs a value") }
    args.removeFirst()
    switch flag {
    case "--vault": vault = URL(fileURLWithPath: value, isDirectory: true)
    case "--records": recordsFile = URL(fileURLWithPath: value)
    case "--state": state = URL(fileURLWithPath: value)
    case "--window-start":
        guard let d = CivilDate(string: value) else { fail("--window-start wants YYYY-MM-DD") }
        options.windowStart = d
    case "--attendee-cap":
        guard let n = Int(value), n >= 0 else { fail("--attendee-cap wants a number") }
        options.attendeeCap = n
    case "--confirm": options.confirmedEmpty.insert(value)
    default: fail("unknown option \(flag)\n\n\(usage)")
    }
}
guard let vault else { fail("--vault is required\n\n\(usage)") }
guard let recordsFile else { fail("--records is required (reading calendars and contacts is not built yet)") }
var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: vault.path, isDirectory: &isDir), isDir.boolValue else {
    fail("no such folder: \(vault.path)")
}

do {
    let records = try JSONDecoder().decode(RecordSet.self, from: Data(contentsOf: recordsFile))
    let store = state.map(ManifestStore.init(url:)) ?? .standard(vault: vault)
    let report = try Sync.run(vault: vault, store: store, accounts: AccountRead.from(records), options: options)
    print(report)
    exit(report.problems.isEmpty ? 0 : 1)
} catch {
    fail("\(error)")
}
