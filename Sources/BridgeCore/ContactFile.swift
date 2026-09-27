import Foundation

/// Label slugs (§2.2).
public enum Labels {
    /// A custom label as a key part: lowercased, every run of characters
    /// outside `a–z` and `0–9` made one `_`, and `_` trimmed off both ends.
    /// "Lake house" → `lake_house`. Nil when nothing is left, and the value
    /// then takes the bare kind.
    public static func slug(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var out = ""
        var gap = false
        for c in raw.lowercased().unicodeScalars {
            if ("a"..."z").contains(c) || ("0"..."9").contains(c) {
                if gap, !out.isEmpty { out += "_" }
                out.unicodeScalars.append(c)
                gap = false
            } else {
                gap = true
            }
        }
        return out.isEmpty ? nil : out
    }

    /// How a label reads in the body: its slug with `_` as a space.
    static func shown(_ slug: String) -> String {
        slug.replacingOccurrences(of: "_", with: " ")
    }
}

/// A contact's file (§2.2): frontmatter holding the data, and a body laying the
/// same data out the way Contacts shows it. Both come from one record on every
/// run, so they cannot drift.
public enum ContactFile {
    /// `aliases` are the names the file had before, oldest first (§4.4).
    public static func render(_ c: ContactRecord, source: String, aliases: [String]) -> String {
        frontmatter(c, source: source, aliases: aliases) + "\n" + body(c)
    }

    static func frontmatter(_ c: ContactRecord, source: String, aliases: [String]) -> String {
        var fm = FrontmatterWriter()
        fm.scalar("name", c.name)
        for (key, value) in [
            ("nickname", c.nickname), ("org", c.org), ("department", c.department),
            ("job_title", c.jobTitle),
        ] {
            if let v = nonEmpty(value) { fm.scalar(key, v) }
        }
        for (key, vs) in grouped("phone", c.phones) { fm.values(key, vs, alwaysQuote: true) }
        for (key, vs) in grouped("email", c.emails) { fm.values(key, vs) }
        for (key, vs) in grouped("address", c.addresses.map { Labeled($0.label, oneLine($0.value)) }) {
            fm.values(key, vs)
        }
        for (key, vs) in grouped("url", c.urls) { fm.values(key, vs) }
        if let b = c.birthday { fm.scalar("birthday", b.description) }
        // Never a bare `date:`: in Slate that files the note on the calendar.
        let dates = c.dates.map { Labeled($0.label ?? "other", $0.value.description) }
        for (key, vs) in grouped("date", dates) { fm.values(key, vs) }
        for (key, vs) in grouped("related", c.related) { fm.values(key, vs) }
        for (key, vs) in grouped("social", c.social) { fm.values(key, vs) }
        for (key, vs) in grouped("im", c.im) { fm.values(key, vs) }
        fm.list("aliases", aliases)
        fm.scalar("source", source)
        fm.scalar("uid", c.uid)
        return fm.text
    }

    /// `<kind>_<label>` keys in order of first appearance, each with its
    /// values in card order. Empty values are dropped.
    static func grouped(_ kind: String, _ items: [Labeled<String>]) -> [(String, [String])] {
        var order: [String] = []
        var values: [String: [String]] = [:]
        for item in items {
            guard let v = nonEmpty(item.value) else { continue }
            let key = item.label.map { "\(kind)_\($0)" } ?? kind
            if values[key] == nil { order.append(key) }
            values[key, default: []].append(v)
        }
        return order.map { ($0, values[$0]!) }
    }

    /// An address on one line, its lines joined by `, `.
    static func oneLine(_ lines: [String]) -> String {
        addressLines(lines).joined(separator: ", ")
    }

    static func addressLines(_ lines: [String]) -> [String] {
        lines.compactMap { nonEmpty($0) }
    }

    // MARK: - Body

    static func body(_ c: ContactRecord) -> String {
        var blocks = ["# \(oneLineText(c.name))"]
        let heading = [c.jobTitle, c.department, c.org].compactMap { nonEmpty($0) }
        if !heading.isEmpty { blocks.append(heading.map(oneLineText).joined(separator: " · ")) }
        if let nick = nonEmpty(c.nickname) { blocks.append("“\(oneLineText(nick))”") }

        func section(_ title: String, _ lines: [String]) {
            if !lines.isEmpty { blocks.append("## \(title)\n\n" + lines.joined(separator: "\n")) }
        }
        func item(_ label: String?, _ text: String) -> String {
            label.map { "- \(Labels.shown($0)) · \(text)" } ?? "- \(text)"
        }

        section("Phone", present(c.phones).map { item($0.label, "[\($0.value)](tel:\(telDigits($0.value)))") })
        section("Email", present(c.emails).map { item($0.label, "[\($0.value)](mailto:\($0.value))") })
        section("Address", c.addresses.compactMap { a in
            let lines = addressLines(a.value)
            guard !lines.isEmpty else { return nil }
            // Every line but the last ends in two spaces: a Markdown line break.
            var rows = a.label.map { ["- **\(Labels.shown($0))**"] } ?? []
            rows += lines
            if a.label == nil { rows[0] = "- " + rows[0] }
            return rows.enumerated().map { i, row in
                (i == 0 ? row : "  " + row) + (i < rows.count - 1 ? "  " : "")
            }.joined(separator: "\n")
        })
        section("URL", present(c.urls).map { item($0.label, "<\($0.value)>") })
        if let b = c.birthday { blocks.append("## Birthday\n\n\(b.spelled)") }
        section("Dates", c.dates.map { item($0.label, $0.value.spelled) })
        section("Related", present(c.related).map { item($0.label, $0.value) })
        section("Social", present(c.social).map { item($0.label, $0.value) })
        section("Messaging", present(c.im).map { item($0.label, $0.value) })
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func present(_ items: [Labeled<String>]) -> [Labeled<String>] {
        items.compactMap { i in nonEmpty(i.value).map { Labeled(i.label, oneLineText($0)) } }
    }

    /// A `tel:` target: the digits, and a `+` if the number starts with one.
    static func telDigits(_ number: String) -> String {
        let trimmed = number.drop { $0.isWhitespace }
        let digits = number.filter { $0.isASCII && $0.isNumber }
        return (trimmed.first == "+" ? "+" : "") + digits
    }
}
