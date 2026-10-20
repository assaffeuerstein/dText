import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SnippetEditor: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ExpansionService.self) private var service
    let snippetID: UUID
    @State private var showDelete = false
    @State private var showOptions = true
    @State private var showPreview = false

    private var snippet: Snippet? { store.library.snippets.first { $0.id == snippetID } }
    private func binding<Value>(_ keyPath: WritableKeyPath<Snippet, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { snippet?[keyPath: keyPath] ?? fallback }, set: { value in
            guard var updated = snippet else { return }
            updated[keyPath: keyPath] = value
            store.update(updated)
        })
    }

    var body: some View {
        if let snippet {
            VStack(spacing: 0) {
                header(snippet)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        abbreviationSection(snippet)
                        expansionSection(snippet)
                        DisclosureGroup(isExpanded: $showOptions) {
                            options(snippet).padding(.top, 14)
                        } label: {
                            Label("Expansion rules", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(title: "Notes")
                            TextField("A little context for future you…", text: binding(\.notes, fallback: ""), axis: .vertical)
                                .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(2...5)
                        }
                    }.padding(26)
                }
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.accent)
                    Text(store.saveStatus)
                    Spacer()
                    Text("\(snippet.useCount) expansions")
                    Text("·")
                    Text("\(snippet.body.count) characters")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(16)
            }.background(Theme.canvas)
            .alert("Delete “\(snippet.title)”?", isPresented: $showDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete snippet", role: .destructive) { store.deleteSnippet(snippetID) }
            } message: { Text("This snippet will be removed from your library.") }
        }
    }

    private func header(_ snippet: Snippet) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionCaption(title: "Snippet details")
                TextField("Snippet name", text: binding(\.title, fallback: ""))
                    .textFieldStyle(.plain).font(.system(size: 23, weight: .semibold)).accessibilityIdentifier("snippetTitle")
                Picker("Set", selection: binding(\.setID, fallback: snippet.setID)) {
                    ForEach(store.library.sets) { set in Label(set.name, systemImage: set.symbol).tag(set.id) }
                }.labelsHidden().fixedSize().controlSize(.small)
            }
            Spacer()
            Button {
                var updated = snippet; updated.isFavorite.toggle(); store.update(updated)
            } label: { Image(systemName: snippet.isFavorite ? "star.fill" : "star").foregroundStyle(snippet.isFavorite ? .orange : .secondary) }
                .buttonStyle(.plain).help("Favorite")
            Menu {
                Button("Copy expansion") { service.copy(snippet) }
                Button("Duplicate snippet") { store.duplicate(snippet) }
                Divider()
                Button("Delete snippet…", role: .destructive) { showDelete = true }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(26)
    }

    private func abbreviationSection(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(title: "When I type")
                Spacer()
                Toggle("Enabled", isOn: binding(\.isEnabled, fallback: true))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                if let set = store.library.sets.first(where: { $0.id == snippet.setID }), !set.prefix.isEmpty {
                    Text(set.prefix).foregroundStyle(.tertiary)
                }
                TextField(";shortcut", text: binding(\.abbreviation, fallback: ""))
                    .font(.system(size: 17, weight: .medium, design: .monospaced)).textFieldStyle(.plain)
                    .accessibilityIdentifier("snippetAbbreviation")
                if let set = store.library.sets.first(where: { $0.id == snippet.setID }), !set.suffix.isEmpty {
                    Text(set.suffix).foregroundStyle(.tertiary)
                }
                Image(systemName: "arrow.turn.down.right").font(.system(size: 12)).foregroundStyle(.tertiary)
            }.padding(14).background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
            if !store.conflicts(for: snippet).isEmpty {
                Label("Another enabled snippet uses this abbreviation.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            } else if snippet.matchMode == .regex, (try? NSRegularExpression(pattern: snippet.abbreviation)) == nil {
                Label("This regular expression is invalid.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            } else {
                Text("Tip: start with a semicolon to avoid expanding everyday words.").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private func expansionSection(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(title: "Expand to")
                Spacer()
                Picker("Content type", selection: binding(\.kind, fallback: .text)) {
                    ForEach(ExpansionKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }.labelsHidden().fixedSize().controlSize(.small)
            }
            VStack(spacing: 0) {
                if snippet.kind == .image {
                    imageEditor(snippet)
                } else if snippet.kind == .richText {
                    RichTextEditor(data: binding(\.attachment, fallback: nil), plainText: binding(\.body, fallback: ""))
                        .frame(minHeight: 190, idealHeight: 230)
                } else if showPreview {
                    Text(preview(snippet)).font(.system(size: 13))
                        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading).padding(14).textSelection(.enabled)
                } else {
                    TextEditor(text: binding(\.body, fallback: ""))
                        .font(.system(size: 13, design: snippet.kind == .html ? .monospaced : .default))
                        .scrollContentBackground(.hidden).padding(9).frame(minHeight: 190, idealHeight: 230)
                        .accessibilityIdentifier("snippetBody")
                }
                Divider()
                HStack(spacing: 12) {
                    if snippet.kind == .text || snippet.kind == .html {
                        Menu {
                            tokenButton("Date", token: "{{date:MMMM d, yyyy}}")
                            tokenButton("Time", token: "{{time:HH:mm}}")
                            tokenButton("Clipboard", token: "{{clipboard}}")
                            tokenButton("Cursor position", token: "{{cursor}}")
                            Divider()
                            tokenButton("Input field", token: "{{field:Name}}")
                            tokenButton("Dropdown", token: "{{choice:Option|First|Second}}")
                            tokenButton("UUID", token: "{{uuid}}")
                            tokenButton("Regex capture", token: "{{capture:1}}")
                            Menu("Nested snippet") {
                                ForEach(store.library.snippets.filter { $0.id != snippetID && !$0.abbreviation.isEmpty }) { other in
                                    tokenButton(other.title, token: "{{snippet:\(other.abbreviation)}}")
                                }
                            }
                        } label: { Label("Insert variable", systemImage: "plus.circle") }.menuStyle(.borderlessButton).fixedSize()
                    } else if snippet.kind == .richText {
                        Button("Fonts…") { NSFontManager.shared.orderFrontFontPanel(nil) }.buttonStyle(.plain)
                        Text("Select text to format").foregroundStyle(.tertiary)
                    } else { Text("Original image stored in your library").foregroundStyle(.secondary) }
                    Spacer()
                    if snippet.kind == .text || snippet.kind == .html {
                        Button { showPreview.toggle() } label: { Image(systemName: showPreview ? "pencil" : "eye") }
                            .buttonStyle(.plain).help(showPreview ? "Edit expansion" : "Preview variables")
                    }
                    Button { service.copy(snippet) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy expansion")
                }.font(.system(size: 11)).padding(12).background(Theme.surface.opacity(0.4))
            }.background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
            if snippet.kind == .richText {
                Text("Use ⌘B, ⌘I, and the Fonts panel. Variables are available in plain text and HTML.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func tokenButton(_ name: String, token: String) -> some View {
        Button(name) {
            guard var updated = snippet else { return }
            updated.body += token
            store.update(updated)
        }
    }
    private func preview(_ snippet: Snippet) -> String {
        var renderer = TemplateRenderer(clipboard: "Clipboard content", snippets: store.library.snippets)
        if let fields = try? renderer.inputFields(in: snippet.body) {
            renderer.fields = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.choices.first ?? "[\($0.name)]") })
        }
        do { return try renderer.render(snippet.body).text }
        catch { return error.localizedDescription }
    }
    private func imageEditor(_ snippet: Snippet) -> some View {
        VStack(spacing: 12) {
            if let data = snippet.attachment, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 150)
            } else {
                Image(systemName: "photo.badge.plus").font(.system(size: 32)).foregroundStyle(.tertiary)
                Text("A picture is worth a few keystrokes.").foregroundStyle(.secondary)
            }
            Button("Choose image…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    let data = try Data(contentsOf: url)
                    guard data.count < 10_000_000, NSImage(data: data) != nil else {
                        store.errorMessage = "Choose a supported image smaller than 10 MB."
                        return
                    }
                    var updated = snippet; updated.attachment = data; store.update(updated)
                } catch { store.errorMessage = error.localizedDescription }
            }
        }.font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 190).padding(16)
    }
    private func options(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            LabeledContent("Expand") {
                Picker("Expand", selection: binding(\.matchMode, fallback: .immediate)) {
                    ForEach(MatchMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(maxWidth: 230)
            }
            LabeledContent("Letter case") {
                Picker("Letter case", selection: binding(\.caseMode, fallback: .sensitive)) {
                    ForEach(CaseMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(maxWidth: 230)
            }
            Toggle("Only expand at the start of a word", isOn: binding(\.requiresWordBoundary, fallback: false))
            if snippet.matchMode == .word {
                Toggle("Keep the space or punctuation after expansion", isOn: binding(\.keepDelimiter, fallback: true))
            }
            if snippet.matchMode == .regex {
                Text("Matches the end of what you type. Use {{capture:1}} for the first capture group.").foregroundStyle(.secondary)
            }
        }.font(.system(size: 11)).controlSize(.small).padding(15)
            .background(Theme.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var data: Data?
    @Binding var plainText: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        if let data, let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = plainText
            textView.font = .systemFont(ofSize: 13)
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.plainText = view.string
            parent.data = view.rtf(from: NSRange(location: 0, length: view.string.utf16.count))
        }
    }
}
