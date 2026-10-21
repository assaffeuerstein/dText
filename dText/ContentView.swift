import SwiftUI

enum LibrarySelection: Hashable {
    case all, favorites, recent, set(UUID), playground, statistics, guide
}

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ExpansionService.self) private var service
    @Environment(\.openSettings) private var openSettings
    @State private var selection: LibrarySelection = .all
    @State private var selectedSnippetID: UUID?
    @State private var search = ""
    @State private var editingSetID: UUID?
    @State private var pendingDelete: UUID?
    @State private var sort = "name"

    private var currentSetID: UUID? {
        if case .set(let id) = selection { return id }
        return nil
    }
    private var title: String {
        switch selection {
        case .all: "All snippets"
        case .favorites: "Favorites"
        case .recent: "Recently used"
        case .set(let id): store.library.sets.first(where: { $0.id == id })?.name ?? "Set"
        case .playground: "Playground"
        case .statistics: "Your activity"
        case .guide: "Getting started"
        }
    }
    private var snippets: [Snippet] {
        store.library.snippets.filter { snippet in
            let matchesSelection: Bool
            switch selection {
            case .favorites: matchesSelection = snippet.isFavorite
            case .recent: matchesSelection = snippet.lastUsed != nil
            case .set(let id): matchesSelection = snippet.setID == id
            default: matchesSelection = true
            }
            return matchesSelection && (search.isEmpty || [snippet.title, snippet.abbreviation, snippet.body, snippet.notes]
                .contains(where: { $0.localizedCaseInsensitiveContains(search) }))
        }.sorted { lhs, rhs in
            if selection == .recent || sort == "recent" { return (lhs.lastUsed ?? .distantPast) > (rhs.lastUsed ?? .distantPast) }
            if sort == "uses" { return lhs.useCount > rhs.useCount }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 214)
            Divider()
            switch selection {
            case .playground: PlaygroundView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .statistics: StatisticsView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .guide: GuideView().frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                HSplitView {
                    snippetList.frame(minWidth: 265, idealWidth: 310, maxWidth: 420)
                    if let selectedSnippetID, store.library.snippets.contains(where: { $0.id == selectedSnippetID }) {
                        SnippetEditor(snippetID: selectedSnippetID).id(selectedSnippetID)
                            .frame(minWidth: 410, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView {
                            Label("Make room for better things.", systemImage: "text.cursor")
                        } description: {
                            Text("Select a snippet or create one.\nA few keystrokes can say a lot.")
                        } actions: {
                            Button("New snippet", action: addSnippet).buttonStyle(.borderedProminent)
                        }.frame(minWidth: 410, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Theme.canvas).tint(Theme.accent)
        .frame(minWidth: 960, minHeight: 640).navigationTitle("dText")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { NotificationCenter.default.post(name: .quickSearch, object: nil) } label: {
                    Label("Quick Search", systemImage: "magnifyingglass")
                }.help("Quick Search · ⇧⌘Space")
                Button { service.togglePause() } label: {
                    Label(store.library.preferences.isPaused ? "Resume expansion" : "Pause expansion",
                          systemImage: store.library.preferences.isPaused ? "play" : "pause")
                }
                Button { openSettings() } label: { Label("Settings", systemImage: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: Binding(get: { editingSetID != nil }, set: { if !$0 { editingSetID = nil } })) {
            if let editingSetID { SetEditor(setID: editingSetID) }
        }
        .alert("Delete this set?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete set", role: .destructive) {
                if let pendingDelete { store.deleteSet(pendingDelete) }
                pendingDelete = nil
                selection = .all
            }
        } message: { Text("All snippets in this set will also be deleted. Export the set first if you want a backup.") }
        .alert("dText", isPresented: Binding(get: { store.errorMessage != nil || service.statusMessage != nil }, set: {
            if !$0 { store.errorMessage = nil; service.statusMessage = nil }
        })) {
            Button("OK") { store.errorMessage = nil; service.statusMessage = nil }
        } message: { Text(store.errorMessage ?? service.statusMessage ?? "") }
        .onAppear { if selectedSnippetID == nil { selectedSnippetID = snippets.first?.id } }
        .onChange(of: selection) {
            search = ""
            if !snippets.contains(where: { $0.id == selectedSnippetID }) { selectedSnippetID = snippets.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSnippet)) { _ in addSnippet() }
        .onReceive(NotificationCenter.default.publisher(for: .newSet)) { _ in addSet() }
        .onReceive(NotificationCenter.default.publisher(for: .showGuide)) { _ in selection = .guide }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("dText").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Less typing. More doing.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 30)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SectionCaption(title: "Library").padding(.horizontal, 12).padding(.bottom, 7)
                    sidebarRow("All snippets", symbol: "square.stack.3d.up", target: .all, count: store.library.snippets.count)
                    sidebarRow("Favorites", symbol: "star", target: .favorites, count: store.library.snippets.filter(\.isFavorite).count)
                    sidebarRow("Recently used", symbol: "clock", target: .recent)
                    HStack {
                        SectionCaption(title: "Your sets")
                        Spacer()
                        Button(action: addSet) { Image(systemName: "plus").font(.system(size: 11, weight: .medium)) }
                            .buttonStyle(.plain).help("New set")
                    }.padding(.horizontal, 12).padding(.top, 27).padding(.bottom, 7)
                    ForEach(store.library.sets) { set in
                        sidebarRow(set.name, symbol: set.symbol, target: .set(set.id),
                                   count: store.library.snippets.filter { $0.setID == set.id }.count,
                                   color: Theme.color(set.color), enabled: set.isEnabled)
                        .contextMenu {
                            Button("Edit set…") { editingSetID = set.id }
                            Button(set.isEnabled ? "Disable set" : "Enable set") {
                                var updated = set; updated.isEnabled.toggle(); store.update(updated)
                            }
                            Button("Export set…") { store.exportFile(setID: set.id) }
                            Divider()
                            Button("Delete set…", role: .destructive) { pendingDelete = set.id }
                        }
                    }
                    SectionCaption(title: "Workspace").padding(.horizontal, 12).padding(.top, 27).padding(.bottom, 7)
                    sidebarRow("Playground", symbol: "play.rectangle", target: .playground)
                    sidebarRow("Statistics", symbol: "chart.bar.xaxis", target: .statistics)
                    sidebarRow("Getting started", symbol: "sparkle", target: .guide)
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 12) {
                if !service.accessibilityGranted {
                    Button { service.requestAccessibility() } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "hand.raised").padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Enable text expansion").font(.system(size: 11, weight: .semibold))
                                Text("Allow this copy in macOS settings").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Image(systemName: "arrow.up.right").font(.system(size: 9))
                        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                    Button("Show running app") { service.revealRunningApp() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
                HStack(spacing: 6) {
                    Circle().fill(service.isRunning && !store.library.preferences.isPaused && !service.secureInput ? Theme.accent : .orange)
                        .frame(width: 6, height: 6)
                    Text(service.statusTitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .help(service.keyboardConnectionError ?? service.statusTitle)
                    Spacer()
                }
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                    Text("Stored locally on your Mac")
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(18)
        }.background(Theme.surface.opacity(0.55))
    }

    private func sidebarRow(_ name: String, symbol: String, target: LibrarySelection, count: Int? = nil,
                            color: Color = .secondary, enabled: Bool = true) -> some View {
        Button { selection = target } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(selection == target ? Theme.accent : color).frame(width: 17)
                Text(name).font(.system(size: 12, weight: selection == target ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit() }
                if !enabled { Image(systemName: "pause.circle").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 11).padding(.vertical, 9)
                .background(selection == target ? Theme.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).opacity(enabled ? 1 : 0.55)
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 21, weight: .semibold))
                        Text("\(snippets.count) snippets · a little time, saved").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: addSnippet) { Image(systemName: "plus").font(.system(size: 14, weight: .medium)) }
                        .buttonStyle(.bordered).help("New snippet · ⌘N").accessibilityIdentifier("newSnippetButton")
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Search snippets", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                        .accessibilityIdentifier("snippetSearch")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }.padding(9).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }.padding(20)
            HStack {
                SectionCaption(title: "Abbreviation / expansion")
                Spacer()
                Menu {
                    Picker("Sort by", selection: $sort) {
                        Text("Name").tag("name")
                        Text("Recently used").tag("recent")
                        Text("Most used").tag("uses")
                    }
                    if let id = currentSetID { Button("Edit set…") { editingSetID = id } }
                } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 10)) }
                    .menuStyle(.borderlessButton).fixedSize()
            }.padding(.horizontal, 20).padding(.bottom, 10)
            Divider()
            if snippets.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxHeight: .infinity)
            } else {
                List(selection: $selectedSnippetID) {
                    ForEach(snippets) { snippet in
                        SnippetRow(snippet: snippet, set: store.library.sets.first { $0.id == snippet.setID })
                            .tag(snippet.id).padding(.vertical, 4)
                            .contextMenu {
                                Button("Copy expansion") { service.copy(snippet) }
                                Button("Duplicate") { selectedSnippetID = store.duplicate(snippet) }
                                Button(snippet.isFavorite ? "Remove from favorites" : "Add to favorites") {
                                    var updated = snippet; updated.isFavorite.toggle(); store.update(updated)
                                }
                                Divider()
                                Button("Delete snippet", role: .destructive) { store.deleteSnippet(snippet.id) }
                            }
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                Menu {
                    Button("Import library…") { store.importFile() }
                    Button("Export library…") { store.exportFile() }
                    if let id = currentSetID { Button("Export this set…") { store.exportFile(setID: id) } }
                } label: { Label("Import / Export", systemImage: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
                Spacer()
                Text("⌘N  New snippet").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(14)
        }.background(Theme.canvas)
    }

    private func addSnippet() {
        let setID = currentSetID
        if selection == .favorites || selection == .recent || selection == .playground || selection == .statistics || selection == .guide {
            selection = .all
        }
        search = ""
        selectedSnippetID = store.addSnippet(setID: setID)
    }
    private func addSet() {
        let id = store.addSet()
        selection = .set(id)
        editingSetID = id
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let set: SnippetSet?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: snippet.kind.symbol).font(.system(size: 11)).foregroundStyle(Theme.color(set?.color ?? "mint"))
                Text(snippet.title.isEmpty ? "Untitled snippet" : snippet.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if snippet.isFavorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8)) }
                if !snippet.isEnabled { Image(systemName: "pause.circle").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            HStack(spacing: 9) {
                Text(snippet.abbreviation.isEmpty ? "shortcut" : (set?.prefix ?? "") + snippet.abbreviation + (set?.suffix ?? ""))
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                Text(snippet.kind == .image ? "Image" : snippet.body.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.vertical, 5).opacity(snippet.isEnabled ? 1 : 0.5)
    }
}
