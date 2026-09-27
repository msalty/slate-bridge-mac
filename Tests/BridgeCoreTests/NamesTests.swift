@testable import BridgeCore
import Foundation
import Testing

/// The filename port against Slate's own TypeScript, run over the same inputs
/// (`scripts/name-vectors.mjs`). Any disagreement is a name Slate would not
/// read back as the record's title.
@Suite struct NamesTests {
    struct Vectors: Decodable {
        var safeSegment: [[String]]
        var fitSegment: [[Entry]]
        var numberedSegment: [[Entry]]
        var importedNoteName: [[String]]
    }

    enum Entry: Decodable {
        case s(String), n(Int)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let n = try? c.decode(Int.self) { self = .n(n) } else { self = .s(try c.decode(String.self)) }
        }
        var s: String { if case .s(let v) = self { v } else { "" } }
        var n: Int { if case .n(let v) = self { v } else { 0 } }
    }

    static let vectors: Vectors = try! JSONDecoder().decode(
        Vectors.self, from: Data(contentsOf: fixtures.appendingPathComponent("name-vectors.json")))

    @Test func safeSegmentMatchesTypeScript() {
        for v in Self.vectors.safeSegment {
            #expect(Names.safeSegment(v[0]) == v[1], "safeSegment(\(v[0].debugDescription))")
        }
    }

    @Test func fitSegmentMatchesTypeScript() {
        for v in Self.vectors.fitSegment {
            #expect(Names.fitSegment(v[0].s, v[1].n) == v[2].s, "fitSegment(\(v[0].s.debugDescription), \(v[1].n))")
        }
    }

    @Test func numberedSegmentMatchesTypeScript() {
        for v in Self.vectors.numberedSegment {
            #expect(Names.numberedSegment(v[0].s, v[1].n) == v[2].s)
        }
    }

    @Test func importedNoteNameMatchesTypeScript() {
        for v in Self.vectors.importedNoteName {
            #expect(Names.importedNoteName(v[0], tag: v[1]) == v[2], "importedNoteName(\(v[0].debugDescription))")
        }
    }

    @Test func vectorsCoverTheHardCases() {
        let inputs = Self.vectors.safeSegment.map { $0[0] }
        #expect(inputs.contains { $0.unicodeScalars.contains("\u{85}") }) // not JS whitespace
        #expect(inputs.contains { $0.unicodeScalars.contains("\u{FEFF}") }) // JS whitespace
        #expect(inputs.contains { $0.utf16.count > 120 && $0.contains("🎉") })
    }

    @Test func tagsFromTheExamples() {
        #expect(Naming.sha256Hex("3f2a9c@fastmail.com").hasPrefix("b36177ac"))
        #expect(Naming.sha256Hex("b7c1e0@fastmail.com").hasPrefix("3a77"))
        #expect(Naming.sha256Hex("0e9d44@work.example").hasPrefix("43ce"))
        #expect(Naming.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func eventTagLengthensOnAClash() {
        let uid = "3f2a9c@fastmail.com"
        #expect(Naming.eventName(title: "Design review", uid: uid, taken: { _ in false }) == "Design review (b361)")
        // Taken ignoring case, as APFS does.
        let taken: Set = ["design review (b361)", "design review (b3617)"]
        #expect(Naming.eventName(title: "Design review", uid: uid, taken: { taken.contains($0.lowercased()) })
            == "Design review (b36177)")
        let all = Naming.eventName(title: "Design review", uid: uid, taken: { !$0.hasSuffix(" 2") })
        #expect(all == "Design review (b36177ac) 2")
    }

    @Test func contactNameDisambiguation() {
        let taken: Set = ["jane doe"]
        let pick = { (org: String?, emails: [String], more: Set<String>) in
            Naming.contactName(name: "Jane Doe", org: org, emails: emails,
                               taken: { taken.union(more).contains($0.lowercased()) })
        }
        #expect(pick("Example Corp", [], []) == "Jane Doe (Example Corp)")
        #expect(pick("Example Corp", ["jane.doe@example.org"], ["jane doe (example corp)"]) == "Jane Doe (jane.doe)")
        #expect(pick(nil, [], []) == "Jane Doe 2")
        #expect(pick("A/B: Ltd", [], []) == "Jane Doe (A-B- Ltd)")
        #expect(Naming.contactName(name: "Jane Doe", org: "X", emails: [], taken: { _ in false }) == "Jane Doe")
    }
}
