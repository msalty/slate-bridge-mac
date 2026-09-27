/// The frontmatter block, written the one way it is always written (§6.5).
///
/// Two readers have to agree on every value: YAML, which any other Markdown
/// app uses, and Slate's own regex-level `parseFrontmatter`
/// (`src/core/markdown.ts`), which reads a plain `true` as a boolean, a plain
/// `42` as a number, a value in `[...]` as a list, and a double-quoted value as
/// JSON. A value is written plain when both read it back as the same text, and
/// JSON-quoted otherwise.
public struct FrontmatterWriter {
    private var lines: [String] = []

    public init() {}

    /// `key: value`, quoted only when it has to be — or always, for values
    /// that must stay text however they look (a phone number is digits, and a
    /// digits-only one would come back a number with its leading zero gone).
    public mutating func scalar(_ key: String, _ value: String, alwaysQuote: Bool = false) {
        lines.append("\(key): \(Self.scalarText(value, alwaysQuote: alwaysQuote, inFlow: false))")
    }

    /// `key: value` for one value, `key: [a, b]` for several — a list only
    /// when a label repeats (§2.2).
    public mutating func values(_ key: String, _ values: [String], alwaysQuote: Bool = false) {
        guard let first = values.first else { return }
        if values.count == 1 { return scalar(key, first, alwaysQuote: alwaysQuote) }
        list(key, values, alwaysQuote: alwaysQuote)
    }

    /// `key: [a, b]`, even for one item: a key that is a list by nature
    /// (`aliases`) stays one.
    public mutating func list(_ key: String, _ values: [String], alwaysQuote: Bool = false) {
        guard !values.isEmpty else { return }
        let items = values.map { Self.scalarText($0, alwaysQuote: alwaysQuote, inFlow: true) }
        lines.append("\(key): [\(items.joined(separator: ", "))]")
    }

    /// `key:` then `  - "item"` per item, every item quoted — Slate's own
    /// `setFrontmatterList` shape, since a bare `[[A]]` is a nested list to YAML.
    public mutating func block(_ key: String, _ items: [String]) {
        guard !items.isEmpty else { return }
        lines.append("\(key):")
        for item in items { lines.append("  - \(Self.jsonQuoted(item))") }
    }

    public var text: String { "---\n" + lines.map { $0 + "\n" }.joined() + "---\n" }

    // MARK: - Quoting

    static func scalarText(_ s: String, alwaysQuote: Bool, inFlow: Bool) -> String {
        alwaysQuote || needsQuotes(s, inFlow: inFlow) ? jsonQuoted(s) : s
    }

    /// Whether `s`, written plain, would read back as anything but itself.
    static func needsQuotes(_ s: String, inFlow: Bool) -> Bool {
        let u = Array(s.unicodeScalars)
        guard let first = u.first, let last = u.last else { return true }
        // Slate trims a value; YAML folds and strips around it.
        if first.properties.isWhitespace || last.properties.isWhitespace { return true }
        if u.contains(where: { !isPrintable($0) }) { return true }
        // Indicators that start something other than a plain scalar.
        if "[]{},#&*!|>'\"%@`".unicodeScalars.contains(first) { return true }
        if "-?:".unicodeScalars.contains(first), u.count == 1 || u[1] == " " { return true }
        // A mapping inside the value, or a comment after it.
        if s.contains(": ") || s.hasSuffix(":") || s.contains(" #") { return true }
        // Commas split a flow list and, read by eye, a value; the example
        // vault quotes an address for its commas.
        if s.contains(",") { return true }
        if inFlow, s.contains(where: { "[]{}".contains($0) }) { return true }
        return looksTyped(s)
    }

    /// Plain text either reader would take for a number, a boolean or null.
    static func looksTyped(_ s: String) -> Bool {
        let lower = s.lowercased()
        if ["true", "false", "yes", "no", "on", "off", "y", "n", "null", "~"].contains(lower) {
            return true
        }
        let patterns = [
            #"^[-+]?(\.[0-9]+|[0-9][0-9_]*(\.[0-9_]*)?)([eE][-+]?[0-9]+)?$"#, // ints, floats
            #"^0x[0-9a-fA-F_]+$"#, #"^0o[0-7_]+$"#, #"^0b[01_]+$"#,
            #"^[-+]?\.(inf|Inf|INF)$"#, #"^\.(nan|NaN|NAN)$"#,
            #"^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+(\.[0-9_]*)?$"#, // YAML 1.1 base 60
        ]
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    /// YAML's printable set, less the tab (which a plain scalar may not hold
    /// at either end and nobody means in the middle).
    static func isPrintable(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x20...0x7E, 0x85, 0xA0...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: true
        default: false
        }
    }

    /// `JSON.stringify(s)`, which is what Slate's `unquote` reads back, with
    /// the characters YAML cannot hold raw escaped as well.
    public static func jsonQuoted(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if isPrintable(c) {
                    out.unicodeScalars.append(c)
                } else {
                    let hex = String(c.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
                }
            }
        }
        return out + "\""
    }
}
