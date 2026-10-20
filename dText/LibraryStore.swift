import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class LibraryStore {
    var library: SnippetLibrary {
        didSet { scheduleSave() }
    }
    var errorMessage: String?
    var savedAt: Date?
    private(set) var hasUnsavedChanges = false
    private let fileURL: URL?
    private var saveTask: Task<Void, Never>?
    private var canSave = true

    init(fileURL: URL? = LibraryStore.defaultURL, inMemory: Bool = false) {
        self.fileURL = inMemory ? nil : fileURL
        library = .starter
        guard let fileURL = self.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            library = try Self.decode(Data(contentsOf: fileURL))
            savedAt = Date()
        } catch {
            // Never replace a library that could not be decoded with the starter data.
            canSave = false
            errorMessage = "Your library could not be opened. The original file has been preserved at \(fileURL.path).\n\n\(error.localizedDescription)"
        }
    }

    var saveStatus: String {
        if !canSave { return "Original library preserved · export to save" }
        if hasUnsavedChanges { return "Saving…" }
        return "Saved on this Mac"
    }

    nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "dText/library.json")
    }

    static func decode(_ data: Data) throws -> SnippetLibrary {
        guard data.count <= 50_000_000 else { throw LibraryError.fileTooLarge }
        return try JSONDecoder().decode(SnippetLibrary.self, from: data).validated()
    }

    func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        guard canSave, let fileURL else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(library)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let previous = try Data(contentsOf: fileURL)
                if previous == data { hasUnsavedChanges = false; return }
                try previous.write(to: fileURL.appendingPathExtension("backup"), options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
            savedAt = Date()
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Could not save your library: \(error.localizedDescription)"
        }
    }

    func update(_ snippet: Snippet) {
        guard let index = library.snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var updated = snippet
        updated.modifiedAt = Date()
        library.snippets[index] = updated
    }

    func update(_ set: SnippetSet) {
        guard let index = library.sets.firstIndex(where: { $0.id == set.id }) else { return }
        library.sets[index] = set
    }

    @discardableResult func addSnippet(setID: UUID?) -> UUID {
        let id = setID ?? library.sets.first?.id ?? addSet()
        let snippet = Snippet(setID: id, title: "Untitled snippet", abbreviation: "", body: "")
        library.snippets.insert(snippet, at: 0)
        return snippet.id
    }

    @discardableResult func addSet() -> UUID {
        let set = SnippetSet(name: "New set")
        library.sets.append(set)
        return set.id
    }

    @discardableResult func duplicate(_ snippet: Snippet) -> UUID {
        var copy = snippet
        copy.id = UUID()
        copy.title += " copy"
        copy.abbreviation = ""
        copy.useCount = 0
        copy.charactersSaved = 0
        copy.lastUsed = nil
        copy.createdAt = Date()
        library.snippets.insert(copy, at: 0)
        return copy.id
    }

    func deleteSnippet(_ id: UUID) { library.snippets.removeAll { $0.id == id } }

    func deleteSet(_ id: UUID) {
        library.snippets.removeAll { $0.setID == id }
        library.sets.removeAll { $0.id == id }
    }

    func recordUse(_ id: UUID, insertedCount: Int, triggerCount: Int) {
        guard let index = library.snippets.firstIndex(where: { $0.id == id }) else { return }
        library.snippets[index].useCount += 1
        library.snippets[index].charactersSaved += max(0, insertedCount - triggerCount)
        library.snippets[index].lastUsed = Date()
    }

    func conflicts(for snippet: Snippet) -> [Snippet] {
        guard !snippet.abbreviation.isEmpty,
              let set = library.sets.first(where: { $0.id == snippet.setID }) else { return [] }
        let trigger = set.prefix + snippet.abbreviation + set.suffix
        return library.snippets.filter { other in
            guard other.id != snippet.id, other.isEnabled,
                  let otherSet = library.sets.first(where: { $0.id == other.setID }), otherSet.isEnabled else { return false }
            let otherTrigger = otherSet.prefix + other.abbreviation + otherSet.suffix
            return snippet.caseMode == .sensitive && other.caseMode == .sensitive
                ? trigger == otherTrigger : trigger.lowercased() == otherTrigger.lowercased()
        }
    }

    func merge(_ incoming: SnippetLibrary) throws {
        let validated = try incoming.validated()
        // Remap imported identifiers so importing never overwrites an existing set.
        var remap: [UUID: UUID] = [:]
        for var set in validated.sets {
            let oldID = set.id
            set.id = UUID()
            if library.sets.contains(where: { $0.name == set.name }) { set.name += " (imported)" }
            remap[oldID] = set.id
            library.sets.append(set)
        }
        for var snippet in validated.snippets {
            snippet.id = UUID()
            snippet.setID = remap[snippet.setID]!
            library.snippets.append(snippet)
        }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .tabSeparatedText, .plainText]
        panel.message = "Import a dText JSON library or a tab-separated abbreviation / expansion file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 50_000_000 else { throw LibraryError.fileTooLarge }
            if url.pathExtension.lowercased() == "json" {
                try merge(Self.decode(data))
            } else {
                try merge(Self.parseTSV(String(decoding: data, as: UTF8.self), name: url.deletingPathExtension().lastPathComponent))
            }
        } catch { errorMessage = error.localizedDescription }
    }

    static func parseTSV(_ text: String, name: String) throws -> SnippetLibrary {
        let set = SnippetSet(name: name)
        var snippets: [Snippet] = []
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else { throw LibraryError.invalidTSV }
            if snippets.isEmpty, parts[0].lowercased() == "abbreviation", parts[1].lowercased() == "expansion" { continue }
            snippets.append(Snippet(setID: set.id, title: String(parts[0]), abbreviation: String(parts[0]),
                                    body: String(parts[1]).replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")))
        }
        guard !snippets.isEmpty else { throw LibraryError.invalidTSV }
        return SnippetLibrary(sets: [set], snippets: snippets)
    }

    func exportFile(setID: UUID? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dText Library.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var export = library
            if let setID {
                export.sets = export.sets.filter { $0.id == setID }
                export.snippets = export.snippets.filter { $0.setID == setID }
            }
            export.preferences = AppPreferences()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(export).write(to: url, options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }
}
