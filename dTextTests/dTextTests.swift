import XCTest
@testable import dText

@MainActor
final class dTextTests: XCTestCase {
    private func library(trigger: String = ";hello", body: String = "Hello there", mode: MatchMode = .immediate,
                         caseMode: CaseMode = .sensitive, boundary: Bool = false) -> SnippetLibrary {
        let set = SnippetSet(name: "Tests")
        return SnippetLibrary(sets: [set], snippets: [
            Snippet(setID: set.id, title: "Test", abbreviation: trigger, body: body,
                    matchMode: mode, caseMode: caseMode, requiresWordBoundary: boundary)
        ])
    }

    func testImmediateExpansionConsumesExactlyTheTrigger() {
        var matcher = ExpansionMatcher()
        let lib = library()
        for char in "before ;hell" { XCTAssertNil(matcher.feed(String(char), library: lib, bundleID: "test")) }
        let match = matcher.feed("o", library: lib, bundleID: "test")
        XCTAssertEqual(match?.typedTrigger, ";hello")
        XCTAssertEqual(match?.deleteCount, 6)
        XCTAssertEqual(matcher.buffer, "")
    }

    func testWordExpansionWaitsForSeparatorAndPreservesIt() {
        var matcher = ExpansionMatcher()
        let lib = library(trigger: "teh", body: "the", mode: .word, boundary: true)
        XCTAssertNil(matcher.feed("teh", library: lib, bundleID: "test"))
        let match = matcher.feed(" ", library: lib, bundleID: "test")
        XCTAssertEqual(match?.typedTrigger, "teh")
        XCTAssertEqual(match?.delimiter, " ")
        XCTAssertEqual(match?.deleteCount, 4)
    }

    func testWordBoundaryDoesNotExpandInsideWords() {
        let lib = library(trigger: "teh", mode: .word, boundary: true)
        var matcher = ExpansionMatcher()
        XCTAssertNil(matcher.feed("anteh ", library: lib, bundleID: "test"))
        XCTAssertNotNil(matcher.feed("(teh.", library: lib, bundleID: "test"))
    }

    func testCaseModes() {
        var matcher = ExpansionMatcher()
        XCTAssertNil(matcher.feed(";HELLO", library: library(), bundleID: "test"))
        matcher.reset()
        XCTAssertNotNil(matcher.feed(";HELLO", library: library(caseMode: .insensitive), bundleID: "test"))
    }

    func testAppRulesAndDisabledSetsAndPause() {
        var lib = library()
        lib.sets[0].appScope = .only
        lib.sets[0].bundleIDs = ["allowed"]
        var matcher = ExpansionMatcher()
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "other"))
        XCTAssertNotNil(matcher.feed(";hello", library: lib, bundleID: "allowed"))
        lib.sets[0].isEnabled = false
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "allowed"))
        lib.sets[0].isEnabled = true
        lib.preferences.isPaused = true
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "allowed"))
        lib.preferences.isPaused = false
        lib.preferences.excludedBundleIDs = ["allowed"]
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "allowed"))
    }

    func testExceptAppRuleAndDisabledSnippet() {
        var lib = library()
        lib.sets[0].appScope = .except
        lib.sets[0].bundleIDs = ["excluded"]
        var matcher = ExpansionMatcher()
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "excluded"))
        XCTAssertNotNil(matcher.feed(";hello", library: lib, bundleID: "other"))
        lib.snippets[0].isEnabled = false
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "other"))
    }

    func testSetPrefixSuffix() {
        var lib = library(trigger: "hello")
        lib.sets[0].prefix = ";"
        lib.sets[0].suffix = "."
        var matcher = ExpansionMatcher()
        XCTAssertNil(matcher.feed(";hello", library: lib, bundleID: "test"))
        XCTAssertEqual(matcher.feed(".", library: lib, bundleID: "test")?.deleteCount, 7)
    }

    func testLongestMatchWins() {
        var lib = library(trigger: "llo")
        let long = Snippet(setID: lib.sets[0].id, title: "Long", abbreviation: ";hello", body: "long")
        lib.snippets.append(long)
        var matcher = ExpansionMatcher()
        XCTAssertEqual(matcher.feed(";hello", library: lib, bundleID: "test")?.snippet.id, long.id)
    }

    func testRegexCaptureAndSuffix() {
        var matcher = ExpansionMatcher()
        let lib = library(trigger: #";issue(\d+);"#, body: "Issue {{capture:1}}", mode: .regex)
        let match = matcher.feed("before ;issue42;", library: lib, bundleID: "test")
        XCTAssertEqual(match?.captures, [";issue42;", "42"])
        XCTAssertEqual(match?.deleteCount, 9)
    }

    func testRegexUsesFinalOccurrenceAndRejectsInvalidPatterns() {
        var matcher = ExpansionMatcher()
        let lib = library(trigger: #"\d{2}"#, mode: .regex)
        XCTAssertEqual(matcher.feed("12 and 34", library: lib, bundleID: "test")?.typedTrigger, "34")
        XCTAssertNil(matcher.feed("abc", library: library(trigger: "[", mode: .regex), bundleID: "test"))
    }

    func testPathologicalRegexCannotBlockKeyboardProcessing() {
        var matcher = ExpansionMatcher()
        let start = ContinuousClock.now
        XCTAssertNil(matcher.feed(String(repeating: "a", count: 200),
                                  library: library(trigger: "(a+)+b", mode: .regex), bundleID: "test"))
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(150))
    }

    func testUnicodeBackspaceAndBufferLimit() {
        var matcher = ExpansionMatcher()
        let lib = library(trigger: ";👋", body: "שלום")
        XCTAssertNil(matcher.feed(";x", library: lib, bundleID: "test"))
        matcher.backspace()
        XCTAssertEqual(matcher.feed("👋", library: lib, bundleID: "test")?.deleteCount, 2)
        XCTAssertNil(matcher.feed(String(repeating: "a", count: 1_000), library: lib, bundleID: "test"))
        XCTAssertEqual(matcher.buffer.count, ExpansionMatcher.bufferLimit)
    }

    func testTemplateDateClipboardAndFields() throws {
        let renderer = TemplateRenderer(date: Date(timeIntervalSince1970: 0), clipboard: "clipboard",
                                        fields: ["Name": "Ada"], locale: Locale(identifier: "en_US_POSIX"),
                                        timeZone: TimeZone(secondsFromGMT: 0)!)
        let result = try renderer.render("{{date:yyyy-MM-dd}} {{field:Name}} {{clipboard}} {{choice:Size|Small|Large}}")
        XCTAssertEqual(result.text, "1970-01-01 Ada clipboard Small")
    }

    func testCursorUsesGraphemesAndDoesNotInterpretClipboardTokens() throws {
        let renderer = TemplateRenderer(clipboard: "{{cursor}}")
        let result = try renderer.render("👋{{cursor}}é{{clipboard}}")
        XCTAssertEqual(result.text, "👋é{{cursor}}")
        XCTAssertEqual(result.cursorOffset, 1)
        XCTAssertEqual(result.cursorMovesFromEnd, 11)
    }

    func testAdaptiveCaseAndCursorExpansion() throws {
        let renderer = TemplateRenderer()
        XCTAssertEqual(try renderer.render("hello", typedTrigger: "ABC", caseMode: .adaptive).text, "HELLO")
        XCTAssertEqual(try renderer.render("hello", typedTrigger: "Abc", caseMode: .adaptive).text, "Hello")
        let result = try renderer.render("ß{{cursor}}x", typedTrigger: "ABC", caseMode: .adaptive)
        XCTAssertEqual(result.text, "SSX")
        XCTAssertEqual(result.cursorOffset, 2)
    }

    func testFieldsAreDeduplicatedAndNestedSnippetsRender() throws {
        let lib = library(trigger: ";inner", body: "{{field:Name}} {{choice:Size|S|L}}")
        let renderer = TemplateRenderer(fields: ["Name": "Ada"], snippets: lib.snippets)
        let fields = try renderer.inputFields(in: "{{field:Name}} {{snippet:;inner}}")
        XCTAssertEqual(fields.map(\.name), ["Name", "Size"])
        XCTAssertEqual(try renderer.render("Hi {{snippet:;inner}}").text, "Hi Ada S")
    }

    func testNestedCycleAndMissingSnippetAreRejected() {
        let lib = library(trigger: ";cycle", body: "{{snippet:;cycle}}")
        let renderer = TemplateRenderer(snippets: lib.snippets)
        XCTAssertThrowsError(try renderer.render("{{snippet:;cycle}}"))
        XCTAssertThrowsError(try renderer.render("{{snippet:;missing}}"))
        XCTAssertThrowsError(try renderer.render("{{unknown}}"))
    }

    func testCaptureValuesAreNotEvaluatedAsTemplates() throws {
        let renderer = TemplateRenderer(captures: ["full", "{{field:Name}}"])
        XCTAssertEqual(try renderer.render("{{capture:1}}").text, "{{field:Name}}")
    }

    func testLibraryRoundTripAndImageData() throws {
        var lib = library()
        lib.snippets[0].kind = .image
        lib.snippets[0].attachment = Data([1, 2, 3])
        XCTAssertEqual(try LibraryStore.decode(JSONEncoder().encode(lib)), lib)
    }

    func testImportRemapsIDsAndKeepsExistingContent() throws {
        let store = LibraryStore(inMemory: true)
        store.library = library()
        let incoming = store.library
        try store.merge(incoming)
        XCTAssertEqual(store.library.sets.count, 2)
        XCTAssertEqual(store.library.snippets.count, 2)
        XCTAssertNotEqual(store.library.snippets[0].id, store.library.snippets[1].id)
        XCTAssertNotEqual(store.library.sets[0].id, store.library.sets[1].id)
        XCTAssertNoThrow(try store.library.validated())
    }

    func testInvalidLibraryRejected() throws {
        var lib = library()
        lib.snippets[0].setID = UUID()
        XCTAssertThrowsError(try LibraryStore.decode(JSONEncoder().encode(lib)))
        lib = library()
        lib.version = 2
        XCTAssertThrowsError(try lib.validated())
        lib = library()
        lib.sets.append(lib.sets[0])
        XCTAssertThrowsError(try lib.validated())
    }

    func testTSVImportSupportsHeaderNewlinesAndEmptyExpansion() throws {
        let lib = try LibraryStore.parseTSV("abbreviation\texpansion\n;hi\tHi\\nthere\n;empty\t\n", name: "Imported")
        XCTAssertEqual(lib.snippets.count, 2)
        XCTAssertEqual(lib.snippets[0].body, "Hi\nthere")
        XCTAssertEqual(lib.snippets[1].body, "")
        XCTAssertThrowsError(try LibraryStore.parseTSV("missing tab", name: "Invalid"))
    }

    func testAtomicPersistenceAndCorruptFileIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = directory.appending(path: "library.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(fileURL: url)
        store.library = library()
        store.save()
        XCTAssertEqual(LibraryStore(fileURL: url).library, store.library)
        let corrupt = Data("not a library".utf8)
        try corrupt.write(to: url)
        let broken = LibraryStore(fileURL: url)
        XCTAssertNotNil(broken.errorMessage)
        broken.library.snippets.removeAll()
        broken.save()
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testDeletingSetCascadesAndStatisticsAccumulate() {
        let store = LibraryStore(inMemory: true)
        store.library = library()
        let id = store.library.snippets[0].id
        store.recordUse(id, insertedCount: 20, triggerCount: 6)
        store.recordUse(id, insertedCount: 2, triggerCount: 6)
        XCTAssertEqual(store.library.snippets[0].useCount, 2)
        XCTAssertEqual(store.library.snippets[0].charactersSaved, 14)
        XCTAssertNotNil(store.library.snippets[0].lastUsed)
        store.deleteSet(store.library.sets[0].id)
        XCTAssertTrue(store.library.snippets.isEmpty)
    }
}
