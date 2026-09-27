import Foundation

/// A meeting's file (§2.1, §3, §7).
public enum EventFile {
    /// `attendees` are the rendered items (§6.4), or nil for no key at all.
    public static func render(_ e: EventRecord, source: String, attendees: [String]?) -> String {
        let title = displayTitle(e.title)
        var location = nonEmpty(e.location).map(locationLine)
        var url = nonEmpty(e.url)
        // A location that is nothing but a link is the join link.
        if url == nil, let l = location, JoinLink.isBareURL(l) {
            url = l
            location = nil
        }
        if url == nil { url = e.notes.flatMap { JoinLink.find(in: $0) } }
        if url == nil { url = location.flatMap { JoinLink.find(in: $0) } }

        var fm = FrontmatterWriter()
        fm.scalar("title", title)
        switch e.timing {
        case .allDay(let first, let last):
            fm.scalar("start", first.description)
            fm.scalar("end", max(first, last).description)
        case .timed(let start, let end, let zone):
            fm.scalar("start", start.description)
            fm.scalar("end", max(start, end).description)
            if let zone = nonEmpty(zone) { fm.scalar("tz", zone) }
        }
        if let location { fm.scalar("location", location) }
        if let url { fm.scalar("url", url) }
        if let calendar = nonEmpty(e.calendar) { fm.scalar("calendar", calendar) }
        if let attendees { fm.block("attendees", attendees) }
        fm.scalar("source", source)
        fm.scalar("uid", e.uid)

        var text = fm.text + "\n# \(oneLineText(title))\n"
        if let body = e.notes.flatMap({ ShortBody.make($0, liftedURL: url) }) {
            text += "\n\(body)\n"
        }
        return text
    }

    /// The title as typed, trimmed; `Untitled` when there is none.
    static func displayTitle(_ t: String) -> String {
        nonEmpty(t) ?? "Untitled"
    }

    /// A multi-line location (a room, then a street address) on one line.
    static func locationLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Finding the join link in a description (§2.1 `url`).
public enum JoinLink {
    /// Hosts whose links are a way into a meeting, not something to read.
    static let hosts = [
        "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "gotomeeting.com", "meet.goto.com", "chime.aws",
        "bluejeans.com", "facetime.apple.com", "around.co", "meet.jit.si",
    ]

    /// The first link in `text` to a known meeting host.
    public static func find(in text: String) -> String? {
        for url in urls(in: text) where isJoinURL(url) { return url }
        return nil
    }

    static func urls(in text: String) -> [String] {
        let pattern = #"https?://[^\s<>"'()\[\]]+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            var s = ns.substring(with: $0.range)
            while let last = s.last, ".,;:!?".contains(last) { s.removeLast() }
            return s
        }
    }

    static func isJoinURL(_ s: String) -> Bool {
        guard let host = URLComponents(string: s)?.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isBareURL(_ s: String) -> Bool {
        !s.contains(where: \.isWhitespace) && (s.hasPrefix("https://") || s.hasPrefix("http://"))
    }
}

/// A description made short (§2.1, §7): conference boilerplate cut, the join
/// link taken out of the prose, and roughly 500 characters at most. Six
/// hundred copies of a dial-in footer are real megabytes, real vocabulary, and
/// a search for "meeting" that returns a wall of invites.
public enum ShortBody {
    public static let limit = 500

    public static func make(_ notes: String, liftedURL: String?) -> String? {
        var text = notes.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if looksLikeHTML(text) { text = stripHTML(text) }

        var kept: [String] = []
        for raw in text.components(separatedBy: "\n") {
            if isBoilerplateStart(raw) { break }
            var line = raw
            if let url = liftedURL {
                line = line.replacingOccurrences(of: "<\(url)>", with: "")
                    .replacingOccurrences(of: url, with: "")
            }
            line = String(line.reversed().drop(while: \.isWhitespace).reversed())
            kept.append(line)
        }
        // No run of blank lines longer than one, none at either end.
        var lines: [String] = []
        for line in kept where !(line.isEmpty && (lines.last?.isEmpty ?? true)) { lines.append(line) }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let joined = lines.joined(separator: "\n")
        guard !joined.isEmpty else { return nil }
        return truncate(joined)
    }

    /// Cut at a word boundary near `limit` characters, and say so with `…`.
    static func truncate(_ s: String) -> String {
        guard s.count > limit else { return s }
        var cut = String(s.prefix(limit))
        if let space = cut.lastIndex(where: \.isWhitespace),
           cut.distance(from: space, to: cut.endIndex) < 80 {
            cut = String(cut[..<space])
        }
        cut = String(cut.reversed().drop(while: { $0.isWhitespace || ",;:-".contains($0) }).reversed())
        return cut + "…"
    }

    /// Lines where conference boilerplate begins; everything from one onward
    /// is the invitation's footer, not what the meeting is about.
    static func isBoilerplateStart(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.contains("-::~:~::~:~") { return true } // Google Calendar's fence
        if t.count >= 8, t.allSatisfy({ "-_=~─━═*·•.:".contains($0) }) { return true }
        let lower = t.lowercased()
        return starts.contains { lower.hasPrefix($0) }
    }

    static let starts = [
        "join zoom meeting", "join the zoom meeting", "join with google meet", "join google meet",
        "join by phone", "join on your computer", "join microsoft teams meeting",
        "microsoft teams meeting", "microsoft teams need help", "join the meeting now",
        "click here to join the meeting", "join webex meeting", "join from the meeting link",
        "meeting id:", "passcode:", "one tap mobile", "dial by your location",
        "invitation from google calendar", "please do not edit this section",
        "do not edit this section", "you are receiving this",
    ]

    static func looksLikeHTML(_ s: String) -> Bool {
        s.range(of: #"<(br|p|div|a|span|b|i|ul|li|html)[\s/>]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</li>"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        return t
    }
}
