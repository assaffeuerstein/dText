//
//  dTextApp.swift
//  dText
//
//  Created by Assaf Feuerstein on 20/10/2026.
//

import SwiftUI
@main
struct dTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: LibraryStore
    @State private var service: ExpansionService
    private let quickSearch = QuickSearchController()

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let store = LibraryStore(inMemory: testing)
        _store = State(initialValue: store)
        _service = State(initialValue: ExpansionService(store: store, monitoringEnabled: !testing))
    }

    var body: some Scene {
        Window("dText", id: "library") {
            ContentView()
                .environment(store).environment(service)
                .onAppear {
                    appDelegate.service = service
                    service.showQuickSearch = { quickSearch.show(store: store, service: service) }
                    if !ProcessInfo.processInfo.arguments.contains("--uitesting"),
                       ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { service.start() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .quickSearch)) { _ in
                    quickSearch.show(store: store, service: service)
                }
        }
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Snippet") { NotificationCenter.default.post(name: .newSnippet, object: nil) }.keyboardShortcut("n")
                Button("New Set") { NotificationCenter.default.post(name: .newSet, object: nil) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Import Library…") { store.importFile() }
                Button("Export Library…") { store.exportFile() }
            }
            CommandMenu("Snippets") {
                Button("Quick Search") { quickSearch.show(store: store, service: service) }.keyboardShortcut(.space, modifiers: [.command, .shift])
                Button(store.library.preferences.isPaused ? "Resume Expansion" : "Pause Expansion") { service.togglePause() }
            }
            CommandGroup(replacing: .help) {
                Button("dText Guide") {
                    NotificationCenter.default.post(name: .showGuide, object: nil)
                }
            }
        }
        Settings { SettingsView().environment(store).environment(service) }
        MenuBarExtra("dText", systemImage: store.library.preferences.isPaused ? "text.badge.minus" : "text.cursor") {
            MenuBarContent(store: store, service: service, search: { quickSearch.show(store: store, service: service) })
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var service: ExpansionService?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the expansion service and MenuBarExtra alive without a Dock icon.
        sender.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { service?.stop() }
}

struct MenuBarContent: View {
    let store: LibraryStore
    let service: ExpansionService
    let search: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Text(service.statusTitle)
        Divider()
        Button("Open dText") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "library")
            NSApp.activate()
        }
        Button("Quick Search", action: search)
        Button(store.library.preferences.isPaused ? "Resume Expansion" : "Pause Expansion") { service.togglePause() }
        if !service.accessibilityGranted { Button("Enable Accessibility…") { service.requestAccessibility() } }
        Divider()
        ForEach(Array(store.library.snippets.filter { $0.isFavorite && $0.isEnabled }.prefix(8))) { snippet in
            Button(snippet.title) { service.insertFromSearch(snippet) }
        }
        Divider()
        Button("Settings…") {
            NSApp.setActivationPolicy(.regular)
            openSettings()
            NSApp.activate()
        }
        Button("Quit dText") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
