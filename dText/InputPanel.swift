import AppKit
import SwiftUI

@MainActor
final class InputPanelController: NSObject, NSWindowDelegate {
    static let shared = InputPanelController()
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<[String: String]?, Never>?

    func request(fields: [TemplateField], title: String) async -> [String: String]? {
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Complete snippet"
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: InputFieldsView(fields: fields, title: title) { [weak self] result in
                self?.complete(result)
            })
            panel.center()
            self.panel = panel
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) { complete(nil) }

    private func complete(_ values: [String: String]?) {
        let callback = continuation
        continuation = nil
        panel?.orderOut(nil)
        panel = nil
        callback?.resume(returning: values)
    }
}

struct InputFieldsView: View {
    let fields: [TemplateField]
    let title: String
    let completion: ([String: String]?) -> Void
    @State private var values: [String: String] = [:]
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("A few finishing touches", systemImage: "text.cursor")
                .font(.title2.weight(.semibold))
            Text(title).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(field.name).font(.callout.weight(.medium))
                            if field.choices.isEmpty {
                                TextField(field.name, text: value(for: field))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: field.name)
                            } else {
                                Picker(field.name, selection: value(for: field)) {
                                    ForEach(field.choices, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden()
                            }
                        }
                    }
                }
            }
            HStack {
                Button("Cancel") { completion(nil) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Insert snippet") {
                    completion(Dictionary(uniqueKeysWithValues: fields.map { ($0.name, values[$0.name] ?? $0.choices.first ?? "") }))
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440, height: min(600, CGFloat(fields.count * 70 + 190)))
        .tint(Theme.accent)
        .onAppear { focusedField = fields.first(where: { $0.choices.isEmpty })?.name }
    }

    private func value(for field: TemplateField) -> Binding<String> {
        Binding(get: { values[field.name] ?? field.choices.first ?? "" }, set: { values[field.name] = $0 })
    }
}
