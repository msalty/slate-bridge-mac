@testable import BridgeCore
import Testing

@Suite struct FrontmatterTests {
    func line(_ value: String, quote: Bool = false) -> String {
        var fm = FrontmatterWriter()
        fm.scalar("k", value, alwaysQuote: quote)
        return String(fm.text.dropFirst(4).dropLast(5))
    }

    @Test func plainWhereBothReadersAgree() {
        for v in ["Design review", "2026-09-21T09:30", "2026-09-21", "https://meet.example/abc",
                  "3f2a9c@fastmail.com", "--03-02", "Asia/Tokyo", "Room 4B", "C# club", "50% off",
                  "rock-n-roll", "a: b".replacingOccurrences(of: ": ", with: ":")] {
            #expect(line(v) == "k: \(v)", "\(v)")
        }
    }

    @Test func quotedWhereAReaderWouldMisreadIt() {
        let cases: [(String, String)] = [
            ("", #""""#), (" padded", #"" padded""#), ("Q3: planning", #""Q3: planning""#),
            ("ends:", #""ends:""#), ("note #1", #""note #1""#), ("#1", ##""#1""##),
            ("[[Jane Doe]]", #""[[Jane Doe]]""#), ("12 Rua Augusta, Lisboa", #""12 Rua Augusta, Lisboa""#),
            ("true", #""true""#), ("No", #""No""#), ("null", #""null""#), ("~", #""~""#),
            ("42", #""42""#), ("-3.5", #""-3.5""#), ("1e3", #""1e3""#), ("0x1F", #""0x1F""#),
            ("1:20", #""1:20""#), ("- item", #""- item""#), ("-", #""-""#), ("*bold*", #""*bold*""#),
            ("'quoted'", #""'quoted'""#), (#""quoted""#, #""\"quoted\"""#), ("@handle", #""@handle""#),
            ("two\nlines", #""two\nlines""#), ("tab\there", #""tab\there""#), ("bell\u{7}", #""bell\u0007""#),
            ("back\\slash, x", #""back\\slash, x""#),
        ]
        for (v, want) in cases { #expect(line(v) == "k: \(want)", "\(v.debugDescription)") }
    }

    @Test func phonesAlwaysQuoted() {
        #expect(line("5550143", quote: true) == #"k: "5550143""#)
        #expect(line("+1 555 0143", quote: true) == #"k: "+1 555 0143""#)
    }

    @Test func listsOnlyWhenALabelRepeats() {
        var fm = FrontmatterWriter()
        fm.values("one", ["a@b.c"])
        fm.values("two", ["a@b.c", "Doe, Jane", "x]y"])
        fm.list("aliases", ["JD"])
        fm.block("attendees", ["[[Jane Doe]]", "Sam Ortiz"])
        #expect(fm.text == """
            ---
            one: a@b.c
            two: [a@b.c, "Doe, Jane", "x]y"]
            aliases: [JD]
            attendees:
              - "[[Jane Doe]]"
              - "Sam Ortiz"
            ---

            """)
    }
}
