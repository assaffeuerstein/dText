import AppKit
import ApplicationServices
import Carbon
import Observation
import OSLog

@MainActor @Observable
final class ExpansionService {
    var accessibilityGranted = false
    private(set) var accessibilityAPITrusted = false
    private(set) var keyboardConnectionError: String?
    private(set) var lastPermissionCheck: Date?
    var isRunning = false
    var secureInput = false
    var lastExpansion: String?
    var statusMessage: String?
    var showQuickSearch: (() -> Void)?

    let store: LibraryStore
    private let monitoringEnabled: Bool
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "il.co.druid.dText", category: "Permissions")
    private var matcher = ExpansionMatcher()
    private var isInserting = false
    private var insertionPID: pid_t?
    private var queuedEvents: [CGEvent] = []
    private var pendingTriggerEvent: CGEvent?
    private var insertionInvalidated = false
    private let eventTag: Int64 = 0x6454657874
    private var clipboardSnapshot: [[NSPasteboard.PasteboardType: Data]]?
    private var clipboardChangeCount: Int?
    private var restoreTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?

    init(store: LibraryStore, monitoringEnabled: Bool = true) {
        self.store = store
        self.monitoringEnabled = monitoringEnabled
    }

    var statusTitle: String {
        if store.library.preferences.isPaused { return "Expansion paused" }
        if !accessibilityGranted { return "Permission required" }
        if secureInput { return "Secure input is active" }
        return isRunning ? "Ready to expand" : "Keyboard unavailable"
    }

    var runningAppURL: URL { Bundle.main.bundleURL }

    func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([runningAppURL])
    }

    func start() {
        guard monitoringEnabled, permissionTimer == nil else { return }
        refreshPermissions()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.matcher.reset()
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self?.previousApp = app
                    if self?.isInserting == true, app.processIdentifier != self?.insertionPID {
                        self?.insertionInvalidated = true
                    }
                }
            }
        }
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = app
        }
    }

    func refreshPermissions() {
        let previousAccess = accessibilityGranted
        accessibilityAPITrusted = AXIsProcessTrusted()
        // The engine inserts CGEvents; query that capability directly. AX trust
        // alone can disagree with event access, particularly after changing builds.
        accessibilityGranted = CGPreflightPostEventAccess()
        if lastPermissionCheck == nil || previousAccess != accessibilityGranted {
            logger.notice("Permission check: AX=\(self.accessibilityAPITrusted), postEvents=\(self.accessibilityGranted), app=\(self.runningAppURL.path, privacy: .public)")
        }
        lastPermissionCheck = Date()
        secureInput = IsSecureEventInputEnabled()
        if secureInput || store.library.preferences.isPaused { matcher.reset() }
        if monitoringEnabled && accessibilityGranted && tap == nil { installTap() }
        if !accessibilityGranted && tap != nil { removeTap() }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            isRunning = CGEvent.tapIsEnabled(tap: tap)
        }
        if !accessibilityGranted { keyboardConnectionError = nil }
    }

    func requestAccessibility() {
        // Request the permission used by our filtering event tap and event posting.
        // This only asks macOS to present its consent UI; it never grants access.
        _ = CGRequestPostEventAccess()
        refreshPermissions()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func togglePause() {
        store.library.preferences.isPaused.toggle()
        matcher.reset()
    }

    private func installTap() {
        let types: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .defaultTap, eventsOfInterest: mask,
                                callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<ExpansionService>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated { service.handle(type: type, event: event) }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            keyboardConnectionError = "macOS allows keyboard control, but the keyboard listener could not connect. Stop dText in Xcode and run it again, or quit and reopen this copy."
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = CGEvent.tapIsEnabled(tap: tap)
        keyboardConnectionError = isRunning ? nil : "The keyboard listener is disabled. Recheck permissions or restart this copy of dText."
    }

    private func removeTap() {
        if let tap { CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        matcher.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            matcher.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == eventTag { return Unmanaged.passUnretained(event) }
        guard type == .keyDown || type == .keyUp else {
            matcher.reset()
            if isInserting, NSWorkspace.shared.frontmostApplication?.processIdentifier == insertionPID {
                insertionInvalidated = true
            }
            return Unmanaged.passUnretained(event)
        }
        let frontApp = NSWorkspace.shared.frontmostApplication
        if isInserting, frontApp?.processIdentifier == insertionPID {
            if let copy = event.copy() { queuedEvents.append(copy) }
            return nil
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if key == 49, modifiers == [.maskCommand, .maskShift] {
            matcher.reset()
            DispatchQueue.main.async { [weak self] in self?.showQuickSearch?() }
            return nil
        }
        guard !IsSecureEventInputEnabled(), !store.library.preferences.isPaused,
              let bundleID = frontApp?.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else {
            matcher.reset()
            return Unmanaged.passUnretained(event)
        }
        if modifiers.contains(.maskCommand) || modifiers.contains(.maskControl) {
            matcher.reset()
            return Unmanaged.passUnretained(event)
        }
        if key == 51 { matcher.backspace(); return Unmanaged.passUnretained(event) }
        if [53, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(key) {
            matcher.reset()
            return Unmanaged.passUnretained(event)
        }
        var chars = [UniChar](repeating: 0, count: 32)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        var text = String(utf16CodeUnits: chars, count: length)
        if key == 36 || key == 76 { text = "\n" }
        if key == 48 { text = "\t" }
        guard !text.isEmpty, let match = matcher.feed(text, library: store.library, bundleID: bundleID),
              let target = frontApp else { return Unmanaged.passUnretained(event) }
        // Hold the final keystroke, especially Return/Tab, so it cannot submit or move focus.
        beginInsertion(target: target)
        pendingTriggerEvent = event.copy()
        Task { @MainActor in
            await perform(match, target: target, deliveredCount: max(0, match.deleteCount - text.count))
        }
        return nil
    }

    func insertFromSearch(_ snippet: Snippet) {
        guard monitoringEnabled else { return }
        refreshPermissions()
        guard accessibilityGranted else { requestAccessibility(); return }
        guard let target = previousApp, !target.isTerminated else {
            statusMessage = "Open the destination application before using Quick Search."
            return
        }
        guard let set = store.library.sets.first(where: { $0.id == snippet.setID }),
              snippet.isEnabled, set.isEnabled, set.allows(app: target.bundleIdentifier ?? ""),
              !store.library.preferences.excludedBundleIDs.contains(target.bundleIdentifier ?? "") else {
            statusMessage = "This snippet is disabled for the destination application."
            return
        }
        guard !isInserting else { return }
        beginInsertion(target: target)
        target.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            await perform(ExpansionMatch(snippet: snippet, typedTrigger: "", delimiter: ""), target: target, deliveredCount: 0)
        }
    }

    private func beginInsertion(target: NSRunningApplication) {
        isInserting = true
        insertionPID = target.processIdentifier
        insertionInvalidated = false
        queuedEvents = []
        pendingTriggerEvent = nil
    }

    private func finishInsertion(target: NSRunningApplication) {
        let events = (pendingTriggerEvent.map { [$0] } ?? []) + queuedEvents
        pendingTriggerEvent = nil
        queuedEvents = []
        isInserting = false
        insertionPID = nil
        // Send buffered keystrokes only to the app they originally belonged to.
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.postToPid(target.processIdentifier)
        }
    }

    private func perform(_ match: ExpansionMatch, target: NSRunningApplication, deliveredCount: Int) async {
        defer { finishInsertion(target: target) }
        guard !insertionInvalidated, CGPreflightPostEventAccess(), !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
        let snippet = match.snippet
        do {
            restoreClipboardIfOwned()
            var renderer = TemplateRenderer(clipboard: NSPasteboard.general.string(forType: .string) ?? "",
                                            snippets: store.library.snippets, captures: match.captures)
            let hasTemplate = snippet.kind == .text || snippet.kind == .html
            let fields = hasTemplate ? try renderer.inputFields(in: snippet.body) : []
            if !fields.isEmpty {
                guard let values = await InputPanelController.shared.request(fields: fields, title: snippet.title) else {
                    if !insertionInvalidated { target.activate() }
                    return
                }
                renderer.fields = values
                guard !insertionInvalidated else { return }
                target.activate()
                try? await Task.sleep(for: .milliseconds(160))
            }
            guard !insertionInvalidated, CGPreflightPostEventAccess(), !IsSecureEventInputEnabled(), !target.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
            let rendered = hasTemplate
                ? try renderer.render(snippet.body, typedTrigger: match.typedTrigger, caseMode: snippet.caseMode)
                : RenderedExpansion(text: snippet.body, cursorOffset: nil)
            let delimiter = snippet.keepDelimiter ? match.delimiter : ""
            let item = try pasteboardItem(snippet: snippet, rendered: rendered, delimiter: delimiter)
            snapshotClipboard()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([item])
            clipboardChangeCount = NSPasteboard.general.changeCount
            for _ in 0..<deliveredCount { postKey(51, target: target.processIdentifier) }
            postKey(9, flags: .maskCommand, target: target.processIdentifier)
            pendingTriggerEvent = nil
            try? await Task.sleep(for: .milliseconds(100))
            if snippet.kind == .text, rendered.cursorOffset != nil,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                for _ in 0..<(rendered.cursorMovesFromEnd + delimiter.count) { postKey(123, target: target.processIdentifier) }
            }
            store.recordUse(snippet.id, insertedCount: rendered.text.count, triggerCount: match.typedTrigger.count)
            lastExpansion = snippet.title
            if store.library.preferences.playSound { NSSound(named: "Tink")?.play() }
            if store.library.preferences.restoreClipboard {
                restoreTask?.cancel()
                restoreTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self?.restoreClipboardIfOwned()
                }
            } else {
                clipboardSnapshot = nil
                clipboardChangeCount = nil
            }
        } catch { statusMessage = error.localizedDescription }
    }

    private func pasteboardItem(snippet: Snippet, rendered: RenderedExpansion, delimiter: String) throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(rendered.text + delimiter, forType: .string)
        switch snippet.kind {
        case .text: break
        case .html:
            item.setString(rendered.text + delimiter, forType: .html)
        case .richText:
            if let data = snippet.attachment,
               let rich = NSAttributedString(rtf: data, documentAttributes: nil) {
                let result = NSMutableAttributedString(attributedString: rich)
                result.append(NSAttributedString(string: delimiter))
                if let rtf = result.rtf(from: NSRange(location: 0, length: result.length), documentAttributes: [:]) {
                    item.setData(rtf, forType: .rtf)
                }
                item.setString(result.string, forType: .string)
            }
        case .image:
            guard let data = snippet.attachment, let image = NSImage(data: data), let tiff = image.tiffRepresentation else {
                throw NSError(domain: "dText", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add an image before expanding this snippet."])
            }
            item.setData(tiff, forType: .tiff)
        }
        return item
    }

    func copy(_ snippet: Snippet) {
        Task { @MainActor in
            do {
                var renderer = TemplateRenderer(clipboard: NSPasteboard.general.string(forType: .string) ?? "", snippets: store.library.snippets)
                let hasTemplate = snippet.kind == .text || snippet.kind == .html
                let fields = hasTemplate ? try renderer.inputFields(in: snippet.body) : []
                if !fields.isEmpty {
                    guard let values = await InputPanelController.shared.request(fields: fields, title: snippet.title) else { return }
                    renderer.fields = values
                }
                let rendered = hasTemplate ? try renderer.render(snippet.body) : RenderedExpansion(text: snippet.body, cursorOffset: nil)
                let item = try pasteboardItem(snippet: snippet, rendered: rendered, delimiter: "")
                restoreTask?.cancel()
                clipboardSnapshot = nil
                clipboardChangeCount = nil
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([item])
            } catch { statusMessage = error.localizedDescription }
        }
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags = [], target: pid_t) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.postToPid(target)
        }
    }

    private func snapshotClipboard() {
        clipboardSnapshot = NSPasteboard.general.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        } ?? []
    }

    private func restoreClipboardIfOwned() {
        guard let snapshot = clipboardSnapshot else { return }
        defer { clipboardSnapshot = nil; clipboardChangeCount = nil }
        guard clipboardChangeCount == NSPasteboard.general.changeCount else { return }
        NSPasteboard.general.clearContents()
        let items = snapshot.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        NSPasteboard.general.writeObjects(items)
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if let appActivationObserver { NotificationCenter.default.removeObserver(appActivationObserver) }
        appActivationObserver = nil
        removeTap()
        restoreClipboardIfOwned()
        store.save()
    }
}
