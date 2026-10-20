import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ExpansionService.self) private var service
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.library.preferences[keyPath: keyPath] }, set: { store.library.preferences[keyPath: keyPath] = $0 })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BrandMark(size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make yourself at home.").font(.title2.weight(.semibold))
                        Text("A few preferences for your everyday workflow.").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("Text expansion") {
                LabeledContent("Accessibility", value: service.accessibilityGranted ? "Allowed" : "Permission required")
                if !service.accessibilityGranted {
                    Button("Open Accessibility settings…") { service.requestAccessibility() }
                }
                Toggle("Pause all expansions", isOn: preference(\.isPaused))
                Toggle("Restore clipboard after expanding", isOn: preference(\.restoreClipboard))
                Toggle("Play a sound after expanding", isOn: preference(\.playSound))
                LabeledContent("Quick Search") { Keycap(text: "⇧ ⌘ Space") }
            }
            Section("Startup") {
                Toggle("Open dText at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setLoginEnabled
                ))
                .accessibilityIdentifier("openAtLogin")
                if loginStatus == .requiresApproval {
                    Text("Allow dText in System Settings to finish enabling automatic startup.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("Closing the last window removes dText from the Dock. Text expansion keeps running in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Never expand in these applications") {
                ApplicationList(bundleIDs: preference(\.excludedBundleIDs))
            }
            Section("Your library") {
                HStack {
                    Button("Import…") { store.importFile() }
                    Button("Export backup…") { store.exportFile() }
                    Spacer()
                    Button("Show library in Finder") { NSWorkspace.shared.selectFile(LibraryStore.defaultURL.path, inFileViewerRootedAtPath: "") }
                }
                Text("Snippets stay on this Mac. dText does not store or transmit your typing. Password fields using Secure Input are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 580, height: 700).tint(Theme.accent)
            .onAppear { loginStatus = SMAppService.mainApp.status }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginStatus = SMAppService.mainApp.status
            }
            .alert("Login item", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
                Button("OK") { loginError = nil }
            } message: { Text(loginError ?? "") }
    }

    private func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        // Reading system state must not trigger another register/unregister operation.
        loginStatus = SMAppService.mainApp.status
    }
}

struct SetEditor: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let setID: UUID
    private var set: SnippetSet? { store.library.sets.first { $0.id == setID } }
    private func binding<Value>(_ keyPath: WritableKeyPath<SnippetSet, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { set?[keyPath: keyPath] ?? fallback }, set: { value in
            guard var updated = set else { return }
            updated[keyPath: keyPath] = value; store.update(updated)
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Set preferences").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(22)
            Form {
                Section("Organization") {
                    TextField("Name", text: binding(\.name, fallback: ""))
                    Picker("Color", selection: binding(\.color, fallback: "mint")) {
                        ForEach(["mint", "blue", "purple", "orange", "pink"], id: \.self) { color in
                            Text(color.capitalized).tag(color)
                        }
                    }
                    Picker("Icon", selection: binding(\.symbol, fallback: "folder")) {
                        Label("Folder", systemImage: "folder").tag("folder")
                        Label("Everyday", systemImage: "sun.max").tag("sun.max")
                        Label("Work", systemImage: "briefcase").tag("briefcase")
                        Label("Code", systemImage: "chevron.left.forwardslash.chevron.right").tag("chevron.left.forwardslash.chevron.right")
                        Label("Corrections", systemImage: "checkmark.circle").tag("checkmark.circle")
                        Label("Messages", systemImage: "bubble.left").tag("bubble.left")
                    }
                    Toggle("Enable this set", isOn: binding(\.isEnabled, fallback: true))
                }
                Section("Abbreviations") {
                    TextField("Prefix", text: binding(\.prefix, fallback: ""))
                    TextField("Suffix", text: binding(\.suffix, fallback: ""))
                    Text("The prefix and suffix are added to every abbreviation in this set.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Application rules") {
                    Picker("Expand in", selection: binding(\.appScope, fallback: .all)) {
                        ForEach(AppScope.allCases) { Text($0.title).tag($0) }
                    }
                    if set?.appScope != .all { ApplicationList(bundleIDs: binding(\.bundleIDs, fallback: [])) }
                }
            }.formStyle(.grouped)
        }.frame(width: 500, height: 560).tint(Theme.accent)
    }
}

struct ApplicationList: View {
    @Binding var bundleIDs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(bundleIDs, id: \.self) { id in
                HStack {
                    Image(systemName: "app.dashed").foregroundStyle(.secondary)
                    Text(appName(id)).font(.callout)
                    Spacer()
                    Button { bundleIDs.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help("Remove application")
                }
            }
            Button("Add application…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.applicationBundle]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.allowsMultipleSelection = true
                if panel.runModal() == .OK {
                    for url in panel.urls {
                        if let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) { bundleIDs.append(id) }
                    }
                }
            }
        }
    }
    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return url.deletingPathExtension().lastPathComponent
    }
}
