import Foundation

/// One calendar occurrence, as the sources hand it over: plain values, times
/// already on the wall clock of the zone they are written in.
public struct EventRecord: Hashable, Sendable {
    public enum Timing: Hashable, Sendable {
        /// `last` is **inclusive**: a one-day event has `first == last` (§3).
        case allDay(first: CivilDate, last: CivilDate)
        /// Both written in `zone`; no zone means floating, and no `tz:` (§3).
        case timed(start: CivilDateTime, end: CivilDateTime, zone: String?)

        /// The day the file is filed under: the start, as written.
        public var firstDay: CivilDate {
            switch self {
            case .allDay(let first, _): first
            case .timed(let start, _, _): start.date
            }
        }
    }

    /// Stable across runs; for a recurring event, per occurrence (§6.3).
    public var uid: String
    public var title: String
    public var timing: Timing
    public var location: String?
    /// The join link when the source has one as a field of its own.
    public var url: String?
    /// The source calendar's title: Work, Personal, Family.
    public var calendar: String?
    /// The description, raw. Shortened and cleaned when rendered (§7).
    public var notes: String?
    public var attendees: [Attendee]

    public init(
        uid: String, title: String, timing: Timing, location: String? = nil, url: String? = nil,
        calendar: String? = nil, notes: String? = nil, attendees: [Attendee] = []
    ) {
        self.uid = uid
        self.title = title
        self.timing = timing
        self.location = location
        self.url = url
        self.calendar = calendar
        self.notes = notes
        self.attendees = attendees
    }
}

public struct Attendee: Hashable, Sendable, Codable {
    public var name: String?
    public var email: String?
    /// The person running the helper, who is never listed (§6.4).
    public var isCurrentUser: Bool

    public init(name: String? = nil, email: String? = nil, isCurrentUser: Bool = false) {
        self.name = name
        self.email = email
        self.isCurrentUser = isCurrentUser
    }

    enum CodingKeys: String, CodingKey { case name, email, isCurrentUser = "me" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        isCurrentUser = try c.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
    }
}

/// A labelled value. `label` is already a slug (`home`, `lake_house`) or nil
/// for none; the sources map Apple's built-in labels, and custom ones go
/// through `Labels.slug`. For social and messaging it is the service.
public struct Labeled<Value: Hashable & Sendable & Codable>: Hashable, Sendable, Codable {
    public var label: String?
    public var value: Value

    public init(_ label: String?, _ value: Value) {
        self.label = label
        self.value = value
    }
}

/// One contact card, as the sources hand it over.
public struct ContactRecord: Hashable, Sendable {
    public var uid: String
    /// The display name, as the contacts app shows it.
    public var name: String
    public var nickname: String?
    public var org: String?
    public var department: String?
    public var jobTitle: String?
    public var phones: [Labeled<String>]
    public var emails: [Labeled<String>]
    /// Each address as its lines, the way the country writes it: street lines,
    /// then locality/region/postcode, then the country.
    public var addresses: [Labeled<[String]>]
    public var urls: [Labeled<String>]
    public var birthday: PartialDate?
    public var dates: [Labeled<PartialDate>]
    public var related: [Labeled<String>]
    public var social: [Labeled<String>]
    public var im: [Labeled<String>]

    public init(
        uid: String, name: String, nickname: String? = nil, org: String? = nil,
        department: String? = nil, jobTitle: String? = nil, phones: [Labeled<String>] = [],
        emails: [Labeled<String>] = [], addresses: [Labeled<[String]>] = [],
        urls: [Labeled<String>] = [], birthday: PartialDate? = nil,
        dates: [Labeled<PartialDate>] = [], related: [Labeled<String>] = [],
        social: [Labeled<String>] = [], im: [Labeled<String>] = []
    ) {
        self.uid = uid
        self.name = name
        self.nickname = nickname
        self.org = org
        self.department = department
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.addresses = addresses
        self.urls = urls
        self.birthday = birthday
        self.dates = dates
        self.related = related
        self.social = social
        self.im = im
    }
}
