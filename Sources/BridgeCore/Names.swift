/// Exact ports of Slate's filename functions.
///
/// The reference is `src/core/util.ts` (`safeSegment`, `fitSegment`,
/// `numberedSegment`, `SEGMENT_MAX`) and `src/core/eventname.ts`
/// (`importedNoteName`) in msalty/slate. Slate reads an import's name back
/// against its `title:` only while the name is exactly what these would have
/// made, so they must agree with the TypeScript unit for unit:
///
/// - lengths are UTF-16 code units, as JavaScript counts them;
/// - whitespace is JavaScript's `\s` (and `trim()`, which uses the same set),
///   not Swift's or ICU's;
/// - a cut never leaves half a surrogate pair behind.
///
/// `Tests/BridgeCoreTests/NamesTests.swift` checks these against vectors
/// produced by running the TypeScript itself (`scripts/name-vectors.mjs`).
public enum Names {
    /// The longest a path segment may be, in UTF-16 units.
    public static let segmentMax = 120

    /// `safeSegment`: a string made safe as one path segment.
    public static func safeSegment(_ name: String) -> String {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(name.unicodeScalars.count)
        // .replace(UNSAFE, '-'), then .replace(/\s+/g, ' ')
        var inSpace = false
        for c in name.unicodeScalars {
            let s = isUnsafe(c) ? "-" : c
            if isJSWhitespace(s) {
                if !inSpace { scalars.append(" ") }
                inSpace = true
            } else {
                scalars.append(s)
                inSpace = false
            }
        }
        // .trim(): after the collapse every whitespace run is one space.
        while scalars.first == " " { scalars.removeFirst() }
        while scalars.last == " " { scalars.removeLast() }
        // .replace(/[. ]+$/, '')
        while let last = scalars.last, last == "." || last == " " { scalars.removeLast() }
        var s = String(String.UnicodeScalarView(scalars))
        if s.isEmpty { s = "Untitled" }
        if isReservedDeviceName(s) { s = "_" + s }
        return cutUnits(s, segmentMax)
    }

    /// `fitSegment`: a safe segment cut to leave `room` units.
    public static func fitSegment(_ safe: String, _ room: Int) -> String {
        var scalars = Array(cutUnits(safe, room).unicodeScalars)
        while let last = scalars.last, last == "." || last == " " { scalars.removeLast() }
        let s = String(String.UnicodeScalarView(scalars))
        return s.isEmpty ? "Untitled" : s
    }

    /// `numberedSegment`: the `n`th name to try when `safe` is taken.
    public static func numberedSegment(_ safe: String, _ n: Int) -> String {
        if n <= 1 { return safe }
        let counter = " \(n)"
        return fitSegment(safe, segmentMax - counter.utf16.count) + counter
    }

    /// `importedNoteName`: `Standup (a41b)`.
    public static func importedNoteName(_ title: String, tag: String) -> String {
        let tail = " (\(tag))"
        return fitSegment(safeSegment(title), segmentMax - tail.utf16.count) + tail
    }

    /// A name with something in brackets on the end, inside the budget —
    /// `Jane Doe (Example Corp)`. The same shape as `importedNoteName`, for a
    /// contact's disambiguator; the bracketed part is made safe too.
    public static func bracketed(_ name: String, _ extra: String) -> String {
        importedNoteName(name, tag: safeSegment(extra))
    }

    /// `cutUnits`: the first `n` UTF-16 units, without half a character.
    static func cutUnits(_ s: String, _ n: Int) -> String {
        let units = s.utf16
        if units.count <= n { return s }
        var cut = Array(units.prefix(max(0, n)))
        if let last = cut.last, (0xD800...0xDBFF).contains(last) { cut.removeLast() }
        return String(decoding: cut, as: UTF16.self)
    }

    /// `/[<>:"/\\|?*\x00-\x1f]/`
    static func isUnsafe(_ c: Unicode.Scalar) -> Bool {
        if c.value < 0x20 { return true }
        switch c {
        case "<", ">", ":", "\"", "/", "\\", "|", "?", "*": return true
        default: return false
        }
    }

    /// JavaScript's `\s`: WhiteSpace and LineTerminator (ECMA-262).
    static func isJSWhitespace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// `/^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i`
    static func isReservedDeviceName(_ s: String) -> Bool {
        let l = Array(s.utf16)
        func lower(_ u: UInt16) -> UInt16 { (0x41...0x5A).contains(u) ? u + 0x20 : u }
        let w = l.map(lower)
        let ascii = { (x: String) in Array(x.utf16) }
        if w.count == 3 { return [ascii("con"), ascii("prn"), ascii("aux"), ascii("nul")].contains(w) }
        if w.count == 4, let d = w.last, (0x31...0x39).contains(d) {
            let head = Array(w.prefix(3))
            return head == ascii("com") || head == ascii("lpt")
        }
        return false
    }
}
