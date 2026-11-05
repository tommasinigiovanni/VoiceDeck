import Foundation

public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var spelling: String
    public var aliases: [String]
    public init(id: UUID = UUID(), spelling: String, aliases: [String]) {
        self.id = id; self.spelling = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliases = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public enum PersonalVocabulary {
    /// One pass prevents replacement text being changed again by a different dictionary entry.
    /// Unicode word boundaries keep names from matching inside unrelated words.
    public static func correct(_ text: String, entries: [VocabularyEntry]) -> String {
        var replacements: [String: String] = [:]
        for entry in entries where !entry.spelling.isEmpty {
            for variant in [entry.spelling] + entry.aliases where !variant.isEmpty {
                let key = variant.lowercased()
                if replacements[key] == nil { replacements[key] = entry.spelling }
            }
        }
        let variants = replacements.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        guard !variants.isEmpty else { return text }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:" + variants.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        var corrected = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let sourceRange = Range(match.range, in: text), let targetRange = Range(match.range, in: corrected),
                  let replacement = replacements[String(text[sourceRange]).lowercased()] else { continue }
            corrected.replaceSubrange(targetRange, with: replacement)
        }
        return corrected
    }
}
