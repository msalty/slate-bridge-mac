import Foundation

/*
 * Records as JSON: the golden-file inputs, `slate-bridge sync --records`, and
 * `slate-bridge dump`. Times are written the way the file writes them, so a
 * fixture reads like the note it should produce.
 */

extension CivilDate: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = CivilDate(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

extension PartialDate: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = PartialDate(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

extension EventRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case uid, title, start, end, tz, location, url, calendar, notes, attendees
    }

    /// `start`/`end` as the file writes them: a bare date for all-day (with an
    /// inclusive `end`), a date-time otherwise; `tz` only on a timed event.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = try c.decode(String.self, forKey: .start)
        let end = try c.decodeIfPresent(String.self, forKey: .end)
        let tz = try c.decodeIfPresent(String.self, forKey: .tz)
        let bad = { (what: String) in
            DecodingError.dataCorruptedError(forKey: .start, in: c, debugDescription: what)
        }
        let timing: Timing
        if let s = CivilDate(string: start) {
            var e = s
            if let end {
                guard let parsed = CivilDate(string: end) else { throw bad("bad end: \(end)") }
                e = parsed
            }
            guard tz == nil else { throw bad("an all-day event has no tz") }
            timing = .allDay(first: s, last: e)
        } else if let s = CivilDateTime(string: start) {
            guard let end, let e = CivilDateTime(string: end) else { throw bad("a timed event needs an end") }
            timing = .timed(start: s, end: e, zone: tz)
        } else {
            throw bad("bad start: \(start)")
        }
        self.init(
            uid: try c.decode(String.self, forKey: .uid),
            title: try c.decode(String.self, forKey: .title),
            timing: timing,
            location: try c.decodeIfPresent(String.self, forKey: .location),
            url: try c.decodeIfPresent(String.self, forKey: .url),
            calendar: try c.decodeIfPresent(String.self, forKey: .calendar),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            attendees: try c.decodeIfPresent([Attendee].self, forKey: .attendees) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uid, forKey: .uid)
        try c.encode(title, forKey: .title)
        switch timing {
        case .allDay(let first, let last):
            try c.encode(first.description, forKey: .start)
            try c.encode(last.description, forKey: .end)
        case .timed(let start, let end, let zone):
            try c.encode(start.description, forKey: .start)
            try c.encode(end.description, forKey: .end)
            try c.encodeIfPresent(zone, forKey: .tz)
        }
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(calendar, forKey: .calendar)
        try c.encodeIfPresent(notes, forKey: .notes)
        if !attendees.isEmpty { try c.encode(attendees, forKey: .attendees) }
    }
}

extension ContactRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case uid, name, nickname, org, department, jobTitle = "job_title", phones, emails,
             addresses, urls, birthday, dates, related, social, im
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list<T>(_ k: CodingKeys) throws -> [Labeled<T>] {
            try c.decodeIfPresent([Labeled<T>].self, forKey: k) ?? []
        }
        self.init(
            uid: try c.decode(String.self, forKey: .uid),
            name: try c.decode(String.self, forKey: .name),
            nickname: try c.decodeIfPresent(String.self, forKey: .nickname),
            org: try c.decodeIfPresent(String.self, forKey: .org),
            department: try c.decodeIfPresent(String.self, forKey: .department),
            jobTitle: try c.decodeIfPresent(String.self, forKey: .jobTitle),
            phones: try list(.phones), emails: try list(.emails),
            addresses: try list(.addresses), urls: try list(.urls),
            birthday: try c.decodeIfPresent(PartialDate.self, forKey: .birthday),
            dates: try list(.dates), related: try list(.related),
            social: try list(.social), im: try list(.im))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uid, forKey: .uid)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(nickname, forKey: .nickname)
        try c.encodeIfPresent(org, forKey: .org)
        try c.encodeIfPresent(department, forKey: .department)
        try c.encodeIfPresent(jobTitle, forKey: .jobTitle)
        func list<T>(_ v: [Labeled<T>], _ k: CodingKeys) throws {
            if !v.isEmpty { try c.encode(v, forKey: k) }
        }
        try list(phones, .phones)
        try list(emails, .emails)
        try list(addresses, .addresses)
        try list(urls, .urls)
        try c.encodeIfPresent(birthday, forKey: .birthday)
        try list(dates, .dates)
        try list(related, .related)
        try list(social, .social)
        try list(im, .im)
    }
}

/// What `slate-bridge sync --records` reads: every account's records, as the
/// sources would have produced them. An account with `failed` set stands for
/// a read that did not complete.
public struct RecordSet: Codable, Sendable {
    public struct Account: Codable, Sendable {
        /// The provider slug written as `source:`.
        public var source: String
        /// The account's folder under the calendar and contacts roots.
        public var folder: String
        public var contacts: [ContactRecord]?
        public var events: [EventRecord]?
        /// Why the read failed, when it did.
        public var failed: String?

        public init(source: String, folder: String, contacts: [ContactRecord]? = nil,
                    events: [EventRecord]? = nil, failed: String? = nil) {
            self.source = source
            self.folder = folder
            self.contacts = contacts
            self.events = events
            self.failed = failed
        }
    }

    public var accounts: [Account]

    public init(accounts: [Account]) { self.accounts = accounts }
}
