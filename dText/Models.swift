import Foundation

enum ExpansionKind: String, Codable, CaseIterable, Identifiable {
    case text, richText, html, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "Plain text"
        case .richText: "Rich text"
        case .html: "HTML"
        case .image: "Image"
        }
    }
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        }
    }
}

enum MatchMode: String, Codable, CaseIterable, Identifiable {
    case immediate, word, regex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .immediate: "Immediately"
        case .word: "After a word separator"
        case .regex: "Regular expression"
        }
    }
}

enum CaseMode: String, Codable, CaseIterable, Identifiable {
    case sensitive, insensitive, adaptive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sensitive: "Match case"
        case .insensitive: "Ignore case"
        case .adaptive: "Adapt to typed case"
        }
    }
}

enum AppScope: String, Codable, CaseIterable, Identifiable {
    case all, only, except
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All applications"
        case .only: "Only these applications"
        case .except: "All except these applications"
        }
    }
}

struct SnippetSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol = "folder"
    var color = "mint"
    var isEnabled = true
    var prefix = ""
    var suffix = ""
    var appScope: AppScope = .all
    var bundleIDs: [String] = []

    func allows(app: String) -> Bool {
        switch appScope {
        case .all: true
        case .only: bundleIDs.contains(app)
        case .except: !bundleIDs.contains(app)
        }
    }
}

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var setID: UUID
    var title: String
    var abbreviation: String
    var body: String
    var kind: ExpansionKind = .text
    var attachment: Data?
    var matchMode: MatchMode = .immediate
    var caseMode: CaseMode = .sensitive
    var requiresWordBoundary = false
    var keepDelimiter = true
    var isEnabled = true
    var isFavorite = false
    var notes = ""
    var useCount = 0
    var charactersSaved = 0
    var lastUsed: Date?
    var createdAt = Date()
    var modifiedAt = Date()
}

struct AppPreferences: Codable, Equatable {
    var isPaused = false
    var restoreClipboard = true
    var playSound = false
    var excludedBundleIDs: [String] = []
}

struct SnippetLibrary: Codable, Equatable {
    var version = 1
    var sets: [SnippetSet]
    var snippets: [Snippet]
    var preferences = AppPreferences()

    func validated() throws -> SnippetLibrary {
        guard version == 1 else { throw LibraryError.unsupportedVersion }
        let setIDs = Set(sets.map(\.id))
        guard setIDs.count == sets.count,
              Set(snippets.map(\.id)).count == snippets.count,
              snippets.allSatisfy({ setIDs.contains($0.setID) }) else {
            throw LibraryError.invalidLibrary
        }
        return self
    }

    static var starter: SnippetLibrary {
        let everyday = SnippetSet(name: "Everyday", symbol: "sun.max", color: "mint")
        let work = SnippetSet(name: "Work", symbol: "briefcase", color: "blue")
        let development = SnippetSet(name: "Development", symbol: "chevron.left.forwardslash.chevron.right", color: "purple")
        let corrections = SnippetSet(name: "Auto-corrections", symbol: "checkmark.circle", color: "orange")
        return SnippetLibrary(sets: [everyday, work, development, corrections], snippets: [
            Snippet(setID: everyday.id, title: "Email address", abbreviation: ";email", body: "hello@example.com", isFavorite: true),
            Snippet(setID: everyday.id, title: "A friendly thank you", abbreviation: ";thanks", body: "Thanks so much for your help. I really appreciate it!"),
            Snippet(setID: everyday.id, title: "Today’s date", abbreviation: ";date", body: "{{date:MMMM d, yyyy}}", isFavorite: true),
            Snippet(setID: everyday.id, title: "On my way", abbreviation: ";omw", body: "On my way — see you soon!"),
            Snippet(setID: everyday.id, title: "Clipboard as plain text", abbreviation: ";clip", body: "{{clipboard}}"),
            Snippet(setID: work.id, title: "Email signature", abbreviation: ";sig", body: "Best regards,\n{{field:Your name}}\n{{field:Role}} · {{field:Company}}", isFavorite: true),
            Snippet(setID: work.id, title: "Meeting follow-up", abbreviation: ";followup", body: "Hi {{field:Name}},\n\nThanks for taking the time to meet today. It was great to discuss {{field:Topic}}.\n\nNext steps:\n{{cursor}}\n\nLooking forward to keeping things moving."),
            Snippet(setID: work.id, title: "Scheduling a call", abbreviation: ";call", body: "Hi {{field:Name}},\n\nWould you be available for a {{choice:Duration|15-minute|30-minute|60-minute}} call this week?\n\nLet me know what works for you."),
            Snippet(setID: development.id, title: "Console log", abbreviation: ";log", body: "console.log({{cursor}});"),
            Snippet(setID: development.id, title: "ISO timestamp", abbreviation: ";iso", body: "{{date:yyyy-MM-dd'T'HH:mm:ssZZZZZ}}"),
            Snippet(setID: development.id, title: "Markdown link", abbreviation: ";link", body: "[{{field:Link text}}]({{clipboard}})"),
            Snippet(setID: corrections.id, title: "the", abbreviation: "teh", body: "the", matchMode: .word, caseMode: .adaptive, requiresWordBoundary: true),
            Snippet(setID: corrections.id, title: "receive", abbreviation: "recieve", body: "receive", matchMode: .word, caseMode: .adaptive, requiresWordBoundary: true),
            Snippet(setID: corrections.id, title: "definitely", abbreviation: "definately", body: "definitely", matchMode: .word, caseMode: .adaptive, requiresWordBoundary: true)
        ])
    }
}

enum LibraryError: LocalizedError {
    case unsupportedVersion, invalidLibrary, invalidTSV, fileTooLarge
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This library was created by a newer version of dText."
        case .invalidLibrary: "The library contains duplicate identifiers or snippets without a set."
        case .invalidTSV: "Each line must contain an abbreviation and expansion separated by a tab."
        case .fileTooLarge: "Choose a library smaller than 50 MB."
        }
    }
}
