import Foundation

struct ExpansionMatch {
    var snippet: Snippet
    var typedTrigger: String
    var delimiter: String
    var captures: [String] = []
    var deleteCount: Int { typedTrigger.count + delimiter.count }
}

/// Pure matching logic shared by the global service and the local playground.
struct ExpansionMatcher {
    static let bufferLimit = 256
    private(set) var buffer = ""

    mutating func reset() { buffer = "" }
    mutating func backspace() { if !buffer.isEmpty { buffer.removeLast() } }

    mutating func feed(_ text: String, library: SnippetLibrary, bundleID: String) -> ExpansionMatch? {
        guard !library.preferences.isPaused,
              !library.preferences.excludedBundleIDs.contains(bundleID) else { reset(); return nil }
        buffer += text
        buffer = String(buffer.suffix(Self.bufferLimit))
        let sets = Dictionary(uniqueKeysWithValues: library.sets.map { ($0.id, $0) })
        var candidates: [ExpansionMatch] = []
        let regexDeadline = ContinuousClock.now + .milliseconds(12)
        for snippet in library.snippets where snippet.isEnabled && !snippet.abbreviation.isEmpty {
            guard let set = sets[snippet.setID], set.isEnabled, set.allows(app: bundleID) else { continue }
            if snippet.matchMode == .regex, ContinuousClock.now >= regexDeadline { continue }
            if let match = Self.match(snippet, set: set, in: buffer) { candidates.append(match) }
        }
        // Longest trigger wins; library order deterministically breaks ties.
        guard let best = candidates.enumerated().max(by: {
            $0.element.typedTrigger.count == $1.element.typedTrigger.count
                ? $0.offset > $1.offset : $0.element.typedTrigger.count < $1.element.typedTrigger.count
        })?.element else { return nil }
        reset()
        return best
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    static func match(_ snippet: Snippet, set: SnippetSet, in buffer: String) -> ExpansionMatch? {
        let trigger = set.prefix + snippet.abbreviation + set.suffix
        var candidate = buffer
        var delimiter = ""
        if snippet.matchMode == .word {
            guard let last = candidate.last, !isWordCharacter(last) else { return nil }
            delimiter = String(candidate.removeLast())
        }
        if snippet.matchMode == .regex {
            // A suffix anchor is part of the compiled pattern so an earlier match cannot hide a later one.
            let pattern = NSRegularExpression.escapedPattern(for: set.prefix)
                + "(?:" + snippet.abbreviation + ")"
                + NSRegularExpression.escapedPattern(for: set.suffix) + "\\z"
            let options: NSRegularExpression.Options = snippet.caseMode == .sensitive ? [] : [.caseInsensitive]
            guard let expression = CompiledExpressions.expression(pattern, options: options),
                  let result = CompiledExpressions.suffixMatch(expression, in: candidate),
                  result.range.length > 0, let range = Range(result.range, in: candidate) else { return nil }
            if snippet.requiresWordBoundary, range.lowerBound != candidate.startIndex,
               isWordCharacter(candidate[candidate.index(before: range.lowerBound)]) { return nil }
            let captures = (0..<result.numberOfRanges).map { index in
                Range(result.range(at: index), in: candidate).map { String(candidate[$0]) } ?? ""
            }
            return ExpansionMatch(snippet: snippet, typedTrigger: String(candidate[range]), delimiter: "", captures: captures)
        }
        guard candidate.count >= trigger.count else { return nil }
        let typed = String(candidate.suffix(trigger.count))
        let matches = snippet.caseMode == .sensitive ? typed == trigger : typed.lowercased() == trigger.lowercased()
        guard matches else { return nil }
        let preceding = candidate.dropLast(trigger.count).last
        if snippet.requiresWordBoundary, let preceding, isWordCharacter(preceding) { return nil }
        return ExpansionMatch(snippet: snippet, typedTrigger: typed, delimiter: delimiter)
    }
}

/// Avoid compiling every expression for every key, and bound ICU backtracking time.
private enum CompiledExpressions {
    static var cache: [String: NSRegularExpression] = [:]

    static func expression(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue):\(pattern)"
        if let cached = cache[key] { return cached }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        if cache.count >= 128 { cache.removeAll(keepingCapacity: true) }
        cache[key] = expression
        return expression
    }

    static func suffixMatch(_ expression: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let deadline = ContinuousClock.now + .milliseconds(5)
        var result: NSTextCheckingResult?
        expression.enumerateMatches(in: text, options: [.reportProgress],
                                    range: NSRange(text.startIndex..., in: text)) { match, _, stop in
            if ContinuousClock.now >= deadline {
                stop.pointee = true
            } else if let match {
                result = match
                stop.pointee = true
            }
        }
        return result
    }
}
