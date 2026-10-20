import AppKit
import SwiftUI

struct PlaygroundView: View {
    @Environment(LibraryStore.self) private var store
    @State private var expansionCount = 0
    @State private var resetID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(title: "A little space to experiment")
                    Text("Meet your new superpower.").font(.system(size: 29, weight: .semibold))
                    Text("Try a shortcut below and watch it become something more.").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(Theme.accent.opacity(0.7))
            }
            HStack(spacing: 10) {
                Keycap(text: ";thanks")
                Keycap(text: ";date")
                Keycap(text: ";log")
                Text("or any of your own shortcuts").font(.caption).foregroundStyle(.secondary)
            }
            PlaygroundTextView(store: store) { expansionCount += 1 }.id(resetID)
                .frame(minHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            HStack {
                Label("\(expansionCount) test expansions", systemImage: "checkmark.circle").foregroundStyle(Theme.accent)
                Spacer()
                Button("Clear playground") { resetID = UUID(); expansionCount = 0 }
            }.font(.callout)
            Text("The playground works without Accessibility permission. It previews text and variables; test rich text and images in another app. Test expansions don’t affect your statistics.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(38)
    }
}

struct PlaygroundTextView: NSViewRepresentable {
    let store: LibraryStore
    let onExpansion: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        view.textContainerInset = NSSize(width: 22, height: 22)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.setAccessibilityIdentifier("playgroundInput")
        view.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlaygroundTextView
        var replacing = false
        var inserted = false
        init(_ parent: PlaygroundTextView) { self.parent = parent }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            inserted = !(replacementString ?? "").isEmpty
            return true
        }
        func textDidChange(_ notification: Notification) {
            guard !replacing, inserted, let view = notification.object as? NSTextView else { return }
            inserted = false
            let caret = view.selectedRange().location
            let prefix = (view.string as NSString).substring(to: caret)
            var matcher = ExpansionMatcher()
            var library = parent.store.library
            library.preferences.isPaused = false
            guard let match = matcher.feed(prefix, library: library, bundleID: Bundle.main.bundleIdentifier ?? "") else { return }
            guard match.snippet.kind == .text || match.snippet.kind == .html else { return }
            let start = prefix.index(prefix.endIndex, offsetBy: -match.deleteCount)
            let range = NSRange(start..<prefix.endIndex, in: prefix)
            replacing = true
            view.isEditable = false
            Task { @MainActor in
                defer { self.replacing = false; view.isEditable = true; view.window?.makeFirstResponder(view) }
                do {
                    var renderer = TemplateRenderer(clipboard: NSPasteboard.general.string(forType: .string) ?? "",
                                                    snippets: library.snippets, captures: match.captures)
                    let fields = try renderer.inputFields(in: match.snippet.body)
                    if !fields.isEmpty {
                        guard let values = await InputPanelController.shared.request(fields: fields, title: match.snippet.title) else { return }
                        renderer.fields = values
                    }
                    let result = try renderer.render(match.snippet.body, typedTrigger: match.typedTrigger, caseMode: match.snippet.caseMode)
                    let text = result.text + (match.snippet.keepDelimiter ? match.delimiter : "")
                    view.isEditable = true
                    view.insertText(text, replacementRange: range)
                    if let cursorOffset = result.cursorOffset {
                        let utf16Offset = String(result.text.prefix(cursorOffset)).utf16.count
                        view.setSelectedRange(NSRange(location: range.location + utf16Offset, length: 0))
                    }
                    self.parent.onExpansion()
                } catch { self.parent.store.errorMessage = error.localizedDescription }
            }
        }
    }
}

struct StatisticsView: View {
    @Environment(LibraryStore.self) private var store
    private var totalUses: Int { store.library.snippets.reduce(0) { $0 + $1.useCount } }
    private var saved: Int { store.library.snippets.reduce(0) { $0 + $1.charactersSaved } }
    private var popular: [Snippet] { store.library.snippets.filter { $0.useCount > 0 }.sorted { $0.useCount > $1.useCount } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(title: "Your activity")
                    Text("Small shortcuts. More time.").font(.system(size: 29, weight: .semibold))
                    Text("Every expansion is a little less work for your fingers.").foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    metric("Expansions", value: totalUses.formatted(), symbol: "bolt")
                    metric("Characters saved", value: saved.formatted(), symbol: "keyboard")
                    metric("Minutes saved", value: String(format: "%.1f", Double(saved) / 200), symbol: "clock")
                }
                Text("Time saved is estimated at 40 words per minute, with five characters per word.").font(.caption).foregroundStyle(.tertiary)
                SectionCaption(title: "Your most-used snippets")
                if popular.isEmpty {
                    ContentUnavailableView("Your story starts with a shortcut", systemImage: "chart.bar.xaxis",
                                           description: Text("Expand snippets in your apps to see your activity here."))
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    ForEach(Array(popular.prefix(10).enumerated()), id: \.element.id) { index, snippet in
                        HStack(spacing: 15) {
                            Text(String(format: "%02d", index + 1)).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(snippet.title).font(.callout.weight(.medium))
                                    Spacer()
                                    Text("\(snippet.useCount) expansions").font(.caption).foregroundStyle(.secondary)
                                }
                                GeometryReader { geometry in
                                    Capsule().fill(Theme.accent.opacity(0.65))
                                        .frame(width: max(4, geometry.size.width * Double(snippet.useCount) / Double(popular.first?.useCount ?? 1)))
                                }.frame(height: 4).background(Theme.accent.opacity(0.08), in: Capsule())
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }.padding(38)
        }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(Theme.accent)
            Text(value).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(23)
            .background(Theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.border))
    }
}

struct GuideView: View {
    @Environment(ExpansionService.self) private var service
    private let tokens: [(String, String)] = [
        ("{{date:yyyy-MM-dd}}", "Current date with a custom format"),
        ("{{time:HH:mm}}", "Current local time"),
        ("{{clipboard}}", "Your clipboard’s text"),
        ("{{cursor}}", "Place the cursor here after inserting plain text"),
        ("{{field:Name}}", "Ask for a value before inserting"),
        ("{{choice:Size|Small|Large}}", "Choose a value from a dropdown"),
        ("{{snippet:;sig}}", "Include another snippet by its abbreviation"),
        ("{{capture:1}}", "A regular expression capture group"),
        ("{{uuid}}", "Generate a unique identifier"),
        ("{{tab}} / {{return}}", "Insert a tab or newline character")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                BrandMark(size: 56)
                Text("Your words, on a shortcut.").font(.system(size: 30, weight: .semibold))
                Text("dText turns the things you type over and over into the things you type once.")
                    .font(.title3).foregroundStyle(.secondary)
                step("01", title: "Make it yours", detail: "Choose a sample snippet and replace it with your own words. Create sets for work, personal details, code, or anything you repeat.")
                step("02", title: "Pick a shortcut", detail: "Use a memorable abbreviation such as ;email. You can expand immediately or after a space, and control case and word boundaries.")
                step("03", title: "Take it everywhere", detail: "Enable Accessibility access, open any text editor, and type your shortcut. dText keeps working from the menu bar.")
                if !service.accessibilityGranted {
                    Button("Enable text expansion…") { service.requestAccessibility() }.buttonStyle(.borderedProminent)
                }
                Divider()
                Text("A little more than plain text").font(.title2.weight(.semibold))
                Text("Use these variables in plain text or HTML snippets. Repeated fields share one value. Preview variables with the eye button, or try them in the Playground.")
                    .foregroundStyle(.secondary)
                ForEach(tokens, id: \.0) { token, description in
                    HStack(alignment: .top, spacing: 20) {
                        Text(token).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accent)
                            .frame(width: 240, alignment: .leading).textSelection(.enabled)
                        Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Quick Search").font(.title2.weight(.semibold))
                Text("Press ⇧⌘Space in another app, find your snippet, and press Return to insert it. Escape closes the search. You can also copy any expansion from the library.")
                    .foregroundStyle(.secondary)
                Text("Library files").font(.title2.weight(.semibold))
                Text("Export a complete dText JSON backup or an individual set. Import dText JSON or a tab-separated file with abbreviation and expansion columns. In tab-separated files, use \\n for a new line and \\t for a tab.")
                    .foregroundStyle(.secondary)
            }.padding(38).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(Theme.accent).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }
}
