import AppKit
import SwiftUI

@MainActor
final class QuickSearchController {
    private var panel: NSPanel?
    func show(store: LibraryStore, service: ExpansionService) {
        if panel?.isVisible == true { panel?.orderOut(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 430),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: QuickSearchView(store: store, service: service) { [weak panel] in panel?.orderOut(nil) })
        panel.center()
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }
}

struct QuickSearchView: View {
    let store: LibraryStore
    let service: ExpansionService
    let close: () -> Void
    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool
    private var results: [Snippet] {
        let enabledSets = Set(store.library.sets.filter(\.isEnabled).map(\.id))
        return Array(store.library.snippets.filter {
            $0.isEnabled && enabledSets.contains($0.setID) &&
            (query.isEmpty || [$0.title, $0.abbreviation, $0.body].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.useCount > $1.useCount
        }.prefix(30))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent).font(.title2)
                TextField("What would you like to say?", text: $query).textFieldStyle(.plain)
                    .font(.system(size: 20)).focused($searchFocused).onSubmit(insert)
                Keycap(text: "esc")
            }.padding(24)
            Divider()
            if results.isEmpty {
                ContentUnavailableView.search(text: query).frame(maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(results) { snippet in
                        SnippetRow(snippet: snippet, set: store.library.sets.first { $0.id == snippet.setID })
                            .tag(snippet.id)
                            .onTapGesture(count: 2) { selectedID = snippet.id; insert() }
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                BrandMark(size: 20)
                Text("Quick Search").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("↑ ↓ navigate").font(.caption).foregroundStyle(.secondary)
                Keycap(text: "↩ insert")
                Button("Insert", action: insert).buttonStyle(.borderedProminent).controlSize(.small).disabled(results.isEmpty)
            }.padding(14)
        }
        .frame(width: 580, height: 430).background(Theme.canvas).tint(Theme.accent)
        .onAppear { searchFocused = true; selectedID = results.first?.id }
        .onChange(of: query) { selectedID = results.first?.id }
        .onExitCommand(perform: close)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
    }
    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = results[min(max(index + delta, 0), results.count - 1)].id
    }
    private func insert() {
        guard let snippet = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        close()
        service.insertFromSearch(snippet)
    }
}
