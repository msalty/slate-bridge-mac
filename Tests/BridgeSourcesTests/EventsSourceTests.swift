import BridgeCore
@testable import BridgeSources
import Foundation
import Testing

/// EventKit occurrences as plain values: no store, no permission.
@Suite struct EventsSourceTests {
    let ny = TimeZone(identifier: "America/New_York")!

    func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0, in zone: TimeZone? = nil) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone ?? ny
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    @Test func floatingTimedEvent() throws {
        let raw = RawEvent(externalID: "3f2a9c@fastmail.com", title: "Design review", isAllDay: false,
                           start: at(2026, 9, 21, 9, 30), end: at(2026, 9, 21, 10), timeZone: nil, calendar: "Work")
        let r = try #require(raw.record(floatingZone: ny))
        #expect(r.uid == "3f2a9c@fastmail.com")
        #expect(r.timing == .timed(start: CivilDateTime(CivilDate(2026, 9, 21), 9, 30),
                                   end: CivilDateTime(CivilDate(2026, 9, 21), 10, 0), zone: nil))
    }

    @Test func zonedEventOnItsOwnWallClock() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let raw = RawEvent(externalID: "0e9d44@work.example", title: "Tokyo sync", isAllDay: false,
                           start: at(2026, 10, 1, 0, 30, in: tokyo), end: at(2026, 10, 1, 1, in: tokyo),
                           timeZone: tokyo, calendar: "Work")
        let r = try #require(raw.record(floatingZone: ny))
        #expect(r.timing == .timed(start: CivilDateTime(CivilDate(2026, 10, 1), 0, 30),
                                   end: CivilDateTime(CivilDate(2026, 10, 1), 1, 0), zone: "Asia/Tokyo"))
        // Filed in October, though in New York it is still 30 September.
        #expect(r.timing.firstDay == CivilDate(2026, 10, 1))
    }

    @Test func allDayEndIsInclusiveEitherWayTheStoreEndsIt() throws {
        for end in [at(2026, 9, 23), at(2026, 9, 22, 23, 59, 59)] {
            let raw = RawEvent(externalID: "b7c1e0@fastmail.com", title: "Office closed", isAllDay: true,
                               start: at(2026, 9, 21), end: end, timeZone: nil, calendar: "Personal")
            let r = try #require(raw.record(floatingZone: ny))
            #expect(r.timing == .allDay(first: CivilDate(2026, 9, 21), last: CivilDate(2026, 9, 22)))
        }
    }

    @Test func occurrenceKeepsItsUIDWhenMoved() throws {
        let original = at(2026, 9, 21, 9, 30)
        let moved = RawEvent(externalID: "series@x", title: "Standup", isAllDay: false,
                             start: at(2026, 9, 21, 14), end: at(2026, 9, 21, 14, 15), timeZone: ny,
                             occurrenceDate: original, isRecurring: true, calendar: "Work")
        let r = try #require(moved.record(floatingZone: ny))
        #expect(r.uid == "series@x/20260921T133000Z")
        let single = RawEvent(externalID: "one@x", title: "Once", isAllDay: false, start: original,
                              end: original, timeZone: ny, occurrenceDate: original, calendar: "Work")
        #expect(single.record(floatingZone: ny)?.uid == "one@x")
    }

    @Test func cancelledAndUnidentifiedHaveNoRecord() {
        let base = RawEvent(externalID: "x", title: "T", isAllDay: true, start: at(2026, 9, 21), end: at(2026, 9, 22),
                            timeZone: nil, calendar: "C")
        var cancelled = base
        cancelled.isCancelled = true
        var noID = base
        noID.externalID = nil
        #expect(cancelled.record(floatingZone: ny) == nil)
        #expect(noID.record(floatingZone: ny) == nil)
        let (read, problems) = EventsSource.records([base, cancelled, noID], calendarOrder: ["C"], floatingZone: ny)
        guard case .complete(let rs) = read else { Issue.record("not complete"); return }
        #expect(rs.count == 1)
        #expect(problems == ["1 events have no identifier; skipped"])
    }

    @Test func aMeetingInTwoCalendarsIsProjectedFromTheFirst() {
        let mine = RawEvent(externalID: "m@x", title: "Plan", isAllDay: false, start: at(2026, 9, 21, 9),
                            end: at(2026, 9, 21, 10), timeZone: ny, calendar: "Calendar")
        var shared = mine
        shared.calendar = "Team (shared)"
        let (read, _) = EventsSource.records([shared, mine], calendarOrder: ["Calendar", "Team (shared)"], floatingZone: ny)
        guard case .complete(let rs) = read else { Issue.record("not complete"); return }
        #expect(rs.map(\.calendar) == ["Calendar"])
    }

    @Test func peopleOrganizerFirstRoomsOut() {
        let raw = RawEvent(
            externalID: "x", title: "T", isAllDay: false, start: at(2026, 9, 21, 9), end: at(2026, 9, 21, 10),
            timeZone: nil, calendar: "C",
            attendees: [
                .init(name: "Jane Doe", url: "mailto:jane@example.com"),
                .init(name: "Me", url: "mailto:me@example.com", isCurrentUser: true),
                .init(name: "Room 4B", url: "mailto:room4b@example.com", isResource: true),
                .init(name: "Sam", url: "mailto:sam%2Bwork@example.com"),
                .init(name: "Ghost", url: "urn:uuid:1234"),
                .init(name: "Boss again", url: "MAILTO:Boss@example.com"),
            ],
            organizer: .init(name: "Boss", url: "mailto:boss@example.com"))
        let people = raw.people()
        #expect(people == [
            Attendee(name: "Boss", email: "boss@example.com"),
            Attendee(name: "Jane Doe", email: "jane@example.com"),
            Attendee(name: "Me", email: "me@example.com", isCurrentUser: true),
            Attendee(name: "Sam", email: "sam+work@example.com"),
            Attendee(name: "Ghost", email: nil),
        ])
    }

    @Test func windowIsAMonthBackAndThreeAhead() {
        let (interval, first) = Window.around(at(2026, 9, 27, 18, 30), zone: ny)
        #expect(interval.start == at(2026, 8, 27))
        #expect(interval.end == at(2026, 12, 27))
        #expect(first == CivilDate(2026, 8, 27))
    }
}
