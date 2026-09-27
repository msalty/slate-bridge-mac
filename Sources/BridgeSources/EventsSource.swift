import BridgeCore
@preconcurrency import EventKit
import Foundation

/// One occurrence as EventKit gives it, in plain values: the whole of what
/// the helper reads from an `EKEvent`, so the rules that turn it into a record
/// are tested without a calendar store.
public struct RawEvent: Sendable {
    public var externalID: String?
    public var title: String?
    public var isAllDay: Bool
    public var start: Date
    public var end: Date
    /// Nil for a floating event.
    public var timeZone: TimeZone?
    /// The original start, which a moved occurrence keeps.
    public var occurrenceDate: Date?
    public var isRecurring: Bool
    public var isCancelled: Bool
    public var location: String?
    public var url: String?
    public var calendar: String
    /// Which calendar, when titles repeat: for choosing among copies.
    public var calendarID: String?
    public var notes: String?
    public var attendees: [RawAttendee]
    public var organizer: RawAttendee?

    public struct RawAttendee: Sendable {
        public var name: String?
        /// The participant's URL: `mailto:jane@example.com` for most accounts.
        public var url: String?
        public var isCurrentUser: Bool
        /// A room or a piece of equipment, booked rather than invited.
        public var isResource: Bool

        public init(name: String?, url: String?, isCurrentUser: Bool = false, isResource: Bool = false) {
            self.name = name
            self.url = url
            self.isCurrentUser = isCurrentUser
            self.isResource = isResource
        }
    }

    public init(externalID: String?, title: String?, isAllDay: Bool, start: Date, end: Date,
                timeZone: TimeZone?, occurrenceDate: Date? = nil, isRecurring: Bool = false,
                isCancelled: Bool = false, location: String? = nil, url: String? = nil,
                calendar: String, calendarID: String? = nil, notes: String? = nil,
                attendees: [RawAttendee] = [], organizer: RawAttendee? = nil) {
        self.externalID = externalID
        self.title = title
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.timeZone = timeZone
        self.occurrenceDate = occurrenceDate
        self.isRecurring = isRecurring
        self.isCancelled = isCancelled
        self.location = location
        self.url = url
        self.calendar = calendar
        self.calendarID = calendarID
        self.notes = notes
        self.attendees = attendees
        self.organizer = organizer
    }

    /// The record, or nil for an occurrence that has none: cancelled
    /// (its file goes, §2.1), or with no external identifier to key it by.
    /// `floatingZone` is the Mac's, which EventKit puts all-day and floating
    /// events in.
    public func record(floatingZone: TimeZone) -> EventRecord? {
        guard !isCancelled, let id = externalID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty
        else { return nil }
        let timing: EventRecord.Timing
        if isAllDay {
            let (first, last) = Occurrence.allDayDays(start: start, end: end, zone: floatingZone)
            timing = .allDay(first: first, last: last)
        } else {
            timing = Occurrence.timing(start: start, end: end, eventZone: timeZone, floatingZone: floatingZone)
        }
        let uid = Occurrence.uid(
            externalID: id, recurring: isRecurring, originalStart: occurrenceDate ?? start,
            allDay: isAllDay, floatingZone: floatingZone)
        return EventRecord(
            uid: uid, title: title ?? "", timing: timing, location: location, url: url,
            calendar: calendar, notes: notes, attendees: people())
    }

    /// Everyone invited, organizer included, rooms and equipment left out:
    /// a room is where, not who.
    func people() -> [Attendee] {
        var out: [Attendee] = []
        var seen = Set<String>()
        for p in (organizer.map { [$0] } ?? []) + attendees where !p.isResource {
            let email = Self.email(p.url)
            if let key = email?.lowercased() {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            out.append(Attendee(name: p.name, email: email, isCurrentUser: p.isCurrentUser))
        }
        return out
    }

    /// The address in a participant's URL: `mailto:` for most accounts; some
    /// Exchange servers give a bare address.
    static func email(_ url: String?) -> String? {
        guard var s = url?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("mailto:") { s = String(s.dropFirst(7)) }
        s = s.removingPercentEncoding ?? s
        guard s.contains("@"), !s.contains("/"), !s.contains(":") else { return nil }
        return s
    }
}

/// EventKit, read into plain records (§2.1, §3, §6.3): one account (EKSource)
/// at a time, occurrences in the window, recurrence already expanded by
/// EventKit — no recurrence engine here either.
public final class EventsSource: @unchecked Sendable {
    let store = EKEventStore()

    public init() {}

    public struct Calendar: Codable, Sendable {
        public var id: String
        public var title: String
        public var account: String
        public var accountID: String
        public var accountType: String
        public var type: String
    }

    public static var authorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Shows the system prompt the first time.
    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func calendars() -> [Calendar] {
        store.calendars(for: .event).map {
            Calendar(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "",
                     accountID: $0.source?.sourceIdentifier ?? "", accountType: Self.typeName($0.source?.sourceType),
                     type: Self.typeName($0.type))
        }
    }

    /// The occurrences in `window` from the given calendars, which should be
    /// one account's. Failed unless every calendar is there to read.
    public func read(calendars ids: [String], window: DateInterval, floatingZone: TimeZone = .current)
        -> (read: Read<[EventRecord]>, problems: [String])
    {
        guard Self.authorized else { return (.failed("no permission to read calendars"), []) }
        var cals: [EKCalendar] = []
        for id in ids {
            guard let c = store.calendar(withIdentifier: id) else { return (.failed("a calendar is missing"), []) }
            cals.append(c)
        }
        guard !cals.isEmpty else { return (.complete([]), []) }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: cals)
        let raws = store.events(matching: predicate).map(Self.raw)
        return Self.records(raws, calendarOrder: cals.map(\.calendarIdentifier), floatingZone: floatingZone)
    }

    /// One calendar's occurrences in `window`, as EventKit gives them — for
    /// `dump`. Nil without permission or when the calendar is gone.
    public func rawEvents(calendar id: String, window: DateInterval) -> [RawEvent]? {
        guard Self.authorized, let c = store.calendar(withIdentifier: id) else { return nil }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [c])
        return store.events(matching: predicate).map(Self.raw)
    }

    /// Records from raw occurrences, keeping to the rules that need no store:
    /// cancelled ones dropped, ones with no identifier reported, and a meeting
    /// that sits in two of the account's calendars (yours and one shared with
    /// you, say) projected once, from the first. `calendarOrder` holds
    /// calendar ids, or titles for raws that carry none.
    public static func records(_ raws: [RawEvent], calendarOrder: [String], floatingZone: TimeZone)
        -> (read: Read<[EventRecord]>, problems: [String])
    {
        var problems: [String] = []
        let noID = raws.filter { !$0.isCancelled && ($0.externalID ?? "").isEmpty }.count
        if noID > 0 { problems.append("\(noID) events have no identifier; skipped") }
        let rank = Dictionary(calendarOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var byUID: [String: EventRecord] = [:]
        var order: [String] = []
        let place = { (r: RawEvent) in rank[r.calendarID ?? r.calendar, default: .max] }
        for raw in raws.sorted(by: { place($0) < place($1) }) {
            guard let r = raw.record(floatingZone: floatingZone) else { continue }
            if byUID[r.uid] == nil {
                order.append(r.uid)
                byUID[r.uid] = r
            }
        }
        return (.complete(order.map { byUID[$0]! }), problems)
    }

    static func raw(_ e: EKEvent) -> RawEvent {
        func person(_ p: EKParticipant) -> RawEvent.RawAttendee {
            RawEvent.RawAttendee(
                name: p.name, url: p.url.absoluteString, isCurrentUser: p.isCurrentUser,
                isResource: p.participantType == .room || p.participantType == .resource)
        }
        return RawEvent(
            externalID: e.calendarItemExternalIdentifier, title: e.title, isAllDay: e.isAllDay,
            start: e.startDate, end: e.endDate, timeZone: e.timeZone,
            occurrenceDate: e.occurrenceDate, isRecurring: e.hasRecurrenceRules || e.isDetached,
            isCancelled: e.status == .canceled, location: e.location, url: e.url?.absoluteString,
            calendar: e.calendar?.title ?? "", calendarID: e.calendar?.calendarIdentifier, notes: e.notes,
            attendees: (e.attendees ?? []).map(person), organizer: e.organizer.map(person))
    }

    static func typeName(_ t: EKSourceType?) -> String {
        switch t {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "calDAV"
        case .mobileMe: "iCloud"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        default: "unknown"
        }
    }

    static func typeName(_ t: EKCalendarType) -> String {
        switch t {
        case .local: "local"
        case .calDAV: "calDAV"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }
}

/// The window (§6.3): a month back, three ahead, recomputed each run.
public enum Window {
    public static func around(_ now: Date, monthsBack: Int = 1, monthsAhead: Int = 3,
                              zone: TimeZone = .current) -> (interval: DateInterval, firstDay: CivilDate) {
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .month, value: -monthsBack, to: today)!
        let end = cal.date(byAdding: .month, value: monthsAhead, to: today)!
        return (DateInterval(start: start, end: end), CivilDate(start, in: zone))
    }
}
