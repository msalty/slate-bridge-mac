import Foundation

/// The value with surrounding whitespace off, or nil when nothing is left.
func nonEmpty(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

/// Text on one line, for a heading or a list item: line breaks become spaces.
func oneLineText(_ s: String) -> String {
    s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }.joined(separator: " ")
}
