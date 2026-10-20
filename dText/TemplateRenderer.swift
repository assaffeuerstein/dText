import Foundation

struct TemplateField: Identifiable, Equatable {
    var name: String
    var choices: [String]
    var id: String { name }
}

struct RenderedExpansion: Equatable {
    var text: String
    var cursorOffset: Int?
    var cursorMovesFromEnd: Int { cursorOffset.map { text.count - $0 } ?? 0 }
}

enum TemplateError: LocalizedError {
    case missingSnippet(String), recursiveSnippet, invalidToken(String)
    var errorDescription: String? {
        switch self {
        case .missingSnippet(let name): "The nested snippet “\(name)” could not be found."
        case .recursiveSnippet: "Nested snippets contain a cycle or exceed 10 levels."
        case .invalidToken(let token): "Unknown template token: {{\(token)}}."
        }
    }
}

struct TemplateRenderer {
    var date = Date()
    var clipboard = ""
    var fields: [String: String] = [:]
    var snippets: [Snippet] = []
    var captures: [String] = []
    var locale = Locale.current
    var timeZone = TimeZone.current

    private static let tokenPattern = #"\{\{([^{}]+)\}\}"#

    func expandedTemplate(_ text: String, visited: Set<UUID> = []) throws -> String {
        guard visited.count < 10 else { throw TemplateError.recursiveSnippet }
        return try replacingTokens(in: text) { token in
            guard token.hasPrefix("snippet:") else { return "{{\(token)}}" }
            let name = String(token.dropFirst(8))
            guard let snippet = snippets.first(where: { $0.abbreviation == name }) else { throw TemplateError.missingSnippet(name) }
            guard !visited.contains(snippet.id) else { throw TemplateError.recursiveSnippet }
            return try expandedTemplate(snippet.body, visited: visited.union([snippet.id]))
        }
    }

    func inputFields(in text: String) throws -> [TemplateField] {
        let expanded = try expandedTemplate(text)
        var result: [TemplateField] = []
        let expression = try NSRegularExpression(pattern: Self.tokenPattern)
        for match in expression.matches(in: expanded, range: NSRange(expanded.startIndex..., in: expanded)) {
            guard let range = Range(match.range(at: 1), in: expanded) else { continue }
            let token = String(expanded[range])
            var field: TemplateField?
            if token.hasPrefix("field:") {
                field = TemplateField(name: String(token.dropFirst(6)), choices: [])
            } else if token.hasPrefix("choice:") {
                let parts = token.dropFirst(7).components(separatedBy: "|")
                field = TemplateField(name: parts[0], choices: Array(parts.dropFirst()))
            }
            if let field, !result.contains(where: { $0.name == field.name }) { result.append(field) }
        }
        return result
    }

    func render(_ template: String, typedTrigger: String = "", caseMode: CaseMode = .sensitive) throws -> RenderedExpansion {
        let expanded = try expandedTemplate(template)
        let expression = try NSRegularExpression(pattern: Self.tokenPattern)
        let matches = expression.matches(in: expanded, range: NSRange(expanded.startIndex..., in: expanded))
        var text = ""
        var cursorOffset: Int?
        var position = expanded.startIndex
        for match in matches {
            guard let range = Range(match.range, in: expanded), let tokenRange = Range(match.range(at: 1), in: expanded) else { continue }
            text += expanded[position..<range.lowerBound]
            let token = String(expanded[tokenRange])
            if token == "cursor" {
                if cursorOffset == nil { cursorOffset = text.count }
            } else {
                text += try value(for: token)
            }
            position = range.upperBound
        }
        text += expanded[position...]
        if caseMode == .adaptive, !typedTrigger.isEmpty {
            let letters = typedTrigger.filter(\.isLetter)
            let transform: (String) -> String
            if !letters.isEmpty, letters == letters.uppercased() {
                transform = { $0.uppercased() }
            } else if let first = letters.first, first.isUppercase {
                transform = { $0.prefix(1).uppercased() + $0.dropFirst() }
            } else { transform = { $0 } }
            if let offset = cursorOffset { cursorOffset = transform(String(text.prefix(offset))).count }
            text = transform(text)
        }
        return RenderedExpansion(text: text, cursorOffset: cursorOffset)
    }

    private func value(for token: String) throws -> String {
        if token == "clipboard" { return clipboard }
        if token == "tab" { return "\t" }
        if token == "return" { return "\n" }
        if token == "uuid" { return UUID().uuidString.lowercased() }
        if token.hasPrefix("field:") { return fields[String(token.dropFirst(6))] ?? "" }
        if token.hasPrefix("choice:") {
            let parts = token.dropFirst(7).components(separatedBy: "|")
            return fields[parts[0]] ?? parts.dropFirst().first ?? ""
        }
        if token.hasPrefix("capture:") {
            let index = Int(token.dropFirst(8)) ?? -1
            return captures.indices.contains(index) ? captures[index] : ""
        }
        if token == "date" || token == "time" || token.hasPrefix("date:") || token.hasPrefix("time:") {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            if let colon = token.firstIndex(of: ":") { formatter.dateFormat = String(token[token.index(after: colon)...]) }
            else if token == "date" { formatter.dateStyle = .medium }
            else { formatter.timeStyle = .short }
            return formatter.string(from: date)
        }
        throw TemplateError.invalidToken(token)
    }

    private func replacingTokens(in text: String, replacement: (String) throws -> String) throws -> String {
        let expression = try NSRegularExpression(pattern: Self.tokenPattern)
        var output = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: output), let tokenRange = Range(match.range(at: 1), in: text) else { continue }
            output.replaceSubrange(range, with: try replacement(String(text[tokenRange])))
        }
        return output
    }
}
