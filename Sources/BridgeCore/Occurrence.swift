import Foundation

/// The parts of turning a calendar store's dates into a record that are pure
/// arithmetic, kept here so they are tested without a calendar (§3, §6.3).
public enum Occurrence {
    /// A uid that is the same on every run (§6.3). A single event is its
    /// external identifier as it stands (`3f2a9c@fastmail.com`). One occurrence
    /// of a series adds its *original* start, which a moved occurrence keeps —
    /// so moving it upstream updates the same file:
    /// `<id>/20260921T133000Z`, or `<id>/20260921` for an all-day series.
    public static func uid(
        externalID: String, recurring: Bool, originalStart: Date, allDay: Bool, floatingZone: TimeZone
    ) -> String {
        guard recurring else { return externalID }
        if allDay {
            let d = CivilDate(originalStart, in: floatingZone)
            return "\(externalID)/\(pad(d.year, 4))\(pad(d.month, 2))\(pad(d.day, 2))"
        }
        let t = CivilDateTime(originalStart, in: TimeZone(identifier: "UTC")!)
        return "\(externalID)/\(pad(t.date.year, 4))\(pad(t.date.month, 2))\(pad(t.date.day, 2))"
            + "T\(pad(t.hour, 2))\(pad(t.minute, 2))\(pad(t.second, 2))Z"
    }

    /// An all-day event's days, `last` **inclusive** (§3). A store's end is
    /// either the next midnight (iCalendar's exclusive `DTEND`) or a second
    /// before it; either way the last day is the one holding `end − 1s`.
    public static func allDayDays(start: Date, end: Date, zone: TimeZone) -> (CivilDate, CivilDate) {
        let first = CivilDate(start, in: zone)
        let last = CivilDate(max(start, end.addingTimeInterval(-1)), in: zone)
        return (first, max(first, last))
    }

    /// A timed event on the wall clock of `zone` — the event's own, or the
    /// Mac's for a floating one, which is then written with no `tz:`.
    public static func timing(start: Date, end: Date, eventZone: TimeZone?, floatingZone: TimeZone) -> EventRecord.Timing {
        let zone = eventZone ?? floatingZone
        return .timed(
            start: CivilDateTime(start, in: zone), end: CivilDateTime(max(start, end), in: zone),
            zone: eventZone?.identifier)
    }
}
