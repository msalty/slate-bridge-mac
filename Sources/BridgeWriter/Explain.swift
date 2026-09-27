/// What changed between two versions of a file the helper wrote, by key:
/// for finding what makes a sync rewrite a file it should have left alone,
/// without printing anybody's details.
enum Explain {
    static func changes(from old: String, to new: String) -> [String] {
        let a = parse(old)
        let b = parse(new)
        var out: [String] = []
        for key in unique(a.order + b.order) {
            let x = a.values[key]
            let y = b.values[key]
            if x == y { continue }
            if let x, let y, x.sorted() == y.sorted() {
                out.append("\(key) (order only)")
            } else if x == nil {
                out.append("\(key) (added)")
            } else if y == nil {
                out.append("\(key) (removed)")
            } else if x!.count > 1 || y!.count > 1 {
                let gone = Set(x!).subtracting(y!).count
                let came = Set(y!).subtracting(x!).count
                out.append("\(key) (\(gone) out, \(came) in)")
            } else {
                out.append(key)
            }
        }
        if a.body != b.body { out.append("body") }
        return out
    }

    /// Frontmatter as key → its lines (a block list's items are its lines),
    /// and the body.
    static func parse(_ text: String) -> (order: [String], values: [String: [String]], body: String) {
        var order: [String] = []
        var values: [String: [String]] = [:]
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            return ([], [:], text)
        }
        var last: String?
        for line in lines[1..<end] {
            if line.hasPrefix("  - "), let k = last {
                values[k, default: []].append(String(line.dropFirst(4)))
            } else if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon])
                last = k
                order.append(k)
                let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                values[k] = v.isEmpty ? [] : [v]
            }
        }
        return (order, values, lines[(end + 1)...].joined(separator: "\n"))
    }

    static func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }
}
