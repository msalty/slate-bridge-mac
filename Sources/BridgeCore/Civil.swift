import Foundation

/// A calendar day with no zone: `2026-09-21`.
public struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `zone`.
    public init(_ date: Date, in zone: TimeZone) {
        let c = Self.gregorian(zone).dateComponents([.year, .month, .day], from: date)
        self.init(c.year!, c.month!, c.day!)
    }

    public init?(string: String) {
        let p = string.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(y, m, d)
    }

    public var description: String { "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))" }

    public static func < (a: Self, b: Self) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    static func gregorian(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }
}

/// A wall-clock time with no zone attached: `2026-09-21T09:30`.
public struct CivilDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var date: CivilDate
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(_ date: CivilDate, _ hour: Int, _ minute: Int, _ second: Int = 0) {
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// The wall clock `date` shows in `zone`.
    public init(_ date: Date, in zone: TimeZone) {
        let c = CivilDate.gregorian(zone).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        self.init(CivilDate(c.year!, c.month!, c.day!), c.hour!, c.minute!, c.second!)
    }

    public init?(string: String) {
        let parts = string.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, let d = CivilDate(string: String(parts[0])) else { return nil }
        let t = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        guard t.count == 2 || t.count == 3, t.allSatisfy({ $0.count == 2 }),
              let h = Int(t[0]), let m = Int(t[1]), h < 24, m < 60 else { return nil }
        let s = t.count == 3 ? Int(t[2]) : 0
        guard let s, s < 60 else { return nil }
        self.init(d, h, m, s)
    }

    /// Seconds only when there are any: an event at 09:30 is written `09:30`.
    public var description: String {
        let hm = "\(date)T\(pad(hour, 2)):\(pad(minute, 2))"
        return second == 0 ? hm : "\(hm):\(pad(second, 2))"
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.date, a.hour, a.minute, a.second) < (b.date, b.hour, b.minute, b.second)
    }
}

/// A contact's date: `1984-03-02`, or `--03-02` when the year is not known.
public struct PartialDate: Hashable, Sendable, CustomStringConvertible {
    public var year: Int?
    public var month: Int
    public var day: Int

    public init(year: Int?, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(string: String) {
        if string.hasPrefix("--") {
            let p = string.dropFirst(2).split(separator: "-")
            guard p.count == 2, p.allSatisfy({ $0.count == 2 }),
                  let m = Int(p[0]), let d = Int(p[1]), (1...12).contains(m), (1...31).contains(d)
            else { return nil }
            self.init(year: nil, month: m, day: d)
        } else {
            guard let d = CivilDate(string: string) else { return nil }
            self.init(year: d.year, month: d.month, day: d.day)
        }
    }

    public var description: String {
        let md = "\(pad(month, 2))-\(pad(day, 2))"
        return year.map { "\(pad($0, 4))-\(md)" } ?? "--\(md)"
    }

    /// `2 March 1984`, or `2 March`. English and fixed, never the machine's
    /// locale, so the file comes out the same on every Mac (§2.2, §6.5).
    public var spelled: String {
        let m = Self.months[(month - 1).clamped(to: 0...11)]
        return year.map { "\(day) \(m) \($0)" } ?? "\(day) \(m)"
    }

    static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}

func pad(_ n: Int, _ width: Int) -> String {
    let s = String(abs(n))
    let padded = s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    return n < 0 ? "-" + padded : padded
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
