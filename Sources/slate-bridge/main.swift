import BridgeCore
import BridgeSources
import BridgeWriter
import Foundation

let usage = """
    usage: slate-bridge sync --vault DIR --records FILE [options]
           slate-bridge dump contacts [--container ID]

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

if args.first == "dump" {
    guard args.count >= 2, args[1] == "contacts" else { fail("dump what? contacts\n\n\(usage)") }
    let source = ContactsSource()
    do {
        guard try await source.requestAccess() else { fail("Contacts access was not granted") }
        if args.count == 4, args[2] == "--container" {
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
