@testable import BridgeCore
import Foundation
import Testing

@Suite struct EventTests {
    func timed(_ notes: String? = nil, location: String? = nil, url: String? = nil, zone: String? = nil,
               title: String = "Standup", attendees: [Attendee] = []) -> EventRecord {
        EventRecord(
            uid: "u1", title: title,
            timing: .timed(start: CivilDateTime(CivilDate(2026, 9, 22), 9, 0),
                           end: CivilDateTime(CivilDate(2026, 9, 22), 9, 15), zone: zone),
            location: location, url: url, notes: notes, attendees: attendees)
    }

    func render(_ e: EventRecord) -> String { EventFile.render(e, source: "fastmail", attendees: nil) }

    @Test func minimalFile() {
        #expect(render(timed()) == """
            ---
            title: Standup
            start: 2026-09-22T09:00
            end: 2026-09-22T09:15
            source: fastmail
            uid: u1
            ---

            # Standup

            """)
    }

    @Test func zoneOnlyWhenTheEventHasOne() {
        #expect(render(timed(zone: "Europe/London")).contains("end: 2026-09-22T09:15\ntz: Europe/London\n"))
        #expect(!render(timed()).contains("tz:"))
    }

    @Test func secondsOnlyWhenThereAreAny() {
        #expect(CivilDateTime(CivilDate(2026, 9, 22), 9, 0, 30).description == "2026-09-22T09:00:30")
    }

    @Test func titleKeepsWhatAFilenameCannotHold() {
        let text = render(timed(title: "Q3: plan / review"))
        #expect(text.contains(#"title: "Q3: plan / review""#))
        #expect(text.contains("\n# Q3: plan / review\n"))
        #expect(Naming.eventName(title: "Q3: plan / review", uid: "u1", taken: { _ in false })
            .hasPrefix("Q3- plan - review ("))
        #expect(render(timed(title: "  ")).contains("title: Untitled\n"))
    }

    @Test func joinLinkLiftedOutOfTheProse() {
        let notes = """
            Agenda: the Q3 numbers.

            Join: https://acme.zoom.us/j/123456?pwd=abc
            """
        let text = render(timed(notes))
        #expect(text.contains("url: https://acme.zoom.us/j/123456?pwd=abc\n"))
        #expect(text.hasSuffix("# Standup\n\nAgenda: the Q3 numbers.\n\nJoin:\n"))
    }

    @Test func linkInTheLocationIsTheJoinLink() {
        let text = render(timed(location: "https://meet.google.com/abc-defg-hij"))
        #expect(text.contains("url: https://meet.google.com/abc-defg-hij\n"))
        #expect(!text.contains("location:"))
    }

    @Test func sourceURLWinsAndOrdinaryLinksStay() {
        let text = render(timed("See https://docs.example/spec", url: "https://meet.example/x"))
        #expect(text.contains("url: https://meet.example/x\n"))
        #expect(text.contains("See https://docs.example/spec\n"))
    }

    @Test func multiLineLocationOnOneLine() {
        #expect(render(timed(location: "Room 4B\n12 Main St\n")).contains("location: \"Room 4B, 12 Main St\"\n"))
    }

    @Test func conferenceBoilerplateCut() {
        let google = """
            Quarterly planning.

            -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
            Join with Google Meet: https://meet.google.com/abc-defg-hij
            Or dial: (US) +1 555-0100 PIN: 123
            """
        #expect(ShortBody.make(google, liftedURL: nil) == "Quarterly planning.")
        let teams = """
            Retro for sprint 12
            ________________________________________________________________________________
            Microsoft Teams meeting
            Join on your computer, mobile app or room device
            """
        #expect(ShortBody.make(teams, liftedURL: nil) == "Retro for sprint 12")
        let zoom = "Hi all\n\nJoin Zoom Meeting\nhttps://zoom.us/j/1\nMeeting ID: 1"
        #expect(ShortBody.make(zoom, liftedURL: nil) == "Hi all")
        #expect(ShortBody.make("Join Zoom Meeting\nhttps://zoom.us/j/1", liftedURL: nil) == nil)
    }

    @Test func htmlDescriptionsReadAsText() {
        #expect(ShortBody.make("<p>Line one<br>Line &amp; two</p>", liftedURL: nil) == "Line one\nLine & two")
    }

    @Test func bodiesStayShort() {
        let long = String(repeating: "word ", count: 300)
        let body = ShortBody.make(long, liftedURL: nil)!
        #expect(body.count <= ShortBody.limit + 1)
        #expect(body.hasSuffix("word…"))
        #expect(ShortBody.make("a\n\n\n\nb\r\n\r\n\r\nc  ", liftedURL: nil) == "a\n\nb\n\nc")
    }

    @Test func allDayEndIsInclusive() {
        let zone = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let d = { (day: Int, h: Int, m: Int, s: Int) in
            cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: m, second: s))!
        }
        // iCalendar's exclusive DTEND (next midnight) and EventKit's 23:59:59.
        #expect(Occurrence.allDayDays(start: d(21, 0, 0, 0), end: d(22, 0, 0, 0), zone: zone) == (CivilDate(2026, 9, 21), CivilDate(2026, 9, 21)))
        #expect(Occurrence.allDayDays(start: d(21, 0, 0, 0), end: d(22, 23, 59, 59), zone: zone) == (CivilDate(2026, 9, 21), CivilDate(2026, 9, 22)))
        #expect(Occurrence.allDayDays(start: d(21, 0, 0, 0), end: d(21, 0, 0, 0), zone: zone) == (CivilDate(2026, 9, 21), CivilDate(2026, 9, 21)))
    }

    @Test func occurrenceUIDs() {
        let utc = TimeZone(identifier: "UTC")!
        let at = Date(timeIntervalSince1970: 1_789_997_400) // 2026-09-21T13:30:00Z
        #expect(Occurrence.uid(externalID: "x@y", recurring: false, originalStart: at, allDay: false, floatingZone: utc) == "x@y")
        #expect(Occurrence.uid(externalID: "x@y", recurring: true, originalStart: at, allDay: false, floatingZone: utc) == "x@y/20260921T133000Z")
        let ny = TimeZone(identifier: "America/New_York")!
        #expect(Occurrence.uid(externalID: "x@y", recurring: true, originalStart: at, allDay: false, floatingZone: ny) == "x@y/20260921T133000Z")
        #expect(Occurrence.uid(externalID: "x@y", recurring: true, originalStart: at, allDay: true, floatingZone: ny) == "x@y/20260921")
    }

    @Test func wallClockInTheEventsZone() {
        let at = Date(timeIntervalSince1970: 1_790_782_200) // 2026-09-30T15:30:00Z
        let tokyo = Occurrence.timing(start: at, end: at.addingTimeInterval(1800),
                                      eventZone: TimeZone(identifier: "Asia/Tokyo"), floatingZone: TimeZone(identifier: "UTC")!)
        #expect(tokyo == .timed(start: CivilDateTime(CivilDate(2026, 10, 1), 0, 30),
                                end: CivilDateTime(CivilDate(2026, 10, 1), 1, 0), zone: "Asia/Tokyo"))
        #expect(tokyo.firstDay == CivilDate(2026, 10, 1))
        let floating = Occurrence.timing(start: at, end: at, eventZone: nil, floatingZone: TimeZone(identifier: "UTC")!)
        #expect(floating == .timed(start: CivilDateTime(CivilDate(2026, 9, 30), 15, 30),
                                   end: CivilDateTime(CivilDate(2026, 9, 30), 15, 30), zone: nil))
    }
}
