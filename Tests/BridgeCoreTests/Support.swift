import BridgeCore
import Foundation

/// `Tests/Fixtures`: the example vault from msalty/slate, the records that
/// should produce it, and the filename vectors.
let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

func fixtureText(_ path: String) throws -> String {
    try String(contentsOf: fixtures.appendingPathComponent(path), encoding: .utf8)
}

func fixtureRecords() throws -> RecordSet {
    try JSONDecoder().decode(RecordSet.self, from: Data(contentsOf: fixtures.appendingPathComponent("records.json")))
}

/// The prior names the manifest would hold, from `records.json`.
func fixturePriorNames() throws -> [String: [String: [String]]] {
    struct File: Decodable { var priorNames: [String: [String: [String]]] }
    return try JSONDecoder().decode(File.self, from: Data(contentsOf: fixtures.appendingPathComponent("records.json"))).priorNames
}
