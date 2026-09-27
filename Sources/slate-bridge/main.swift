import BridgeCore
import BridgeWriter
import Foundation

let usage = """
    usage: slate-bridge sync --vault DIR --records FILE [options]

    Runs one sync into DIR from records in FILE (the format of
    Tests/Fixtures/records.json) — the whole pipeline, no permissions needed.

    options:
      --state FILE          the manifest (default: ~/Library/Application
                            Support/slate-bridge-mac/<vault id>.json)
      --window-start DAY    the window's first day, YYYY-MM-DD, to tell an
                            event that slid out of the window from a cancelled one
      --attendee-cap N      no attendee list above N (default 12)
      --confirm SOURCE      delete for SOURCE even though its read came back
                            empty (repeatable)
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("slate-bridge: \(message)\n".utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
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
