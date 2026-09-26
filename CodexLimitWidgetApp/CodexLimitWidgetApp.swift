import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
@preconcurrency import UserNotifications

@main
struct CodexLimitWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: LimitViewModel
    @StateObject private var updateController: AppUpdateController
    @StateObject private var settingsWindowPresenter: SettingsWindowPresenter
    @StateObject private var releaseNotesWindowPresenter: ReleaseNotesWindowPresenter
    @StateObject private var statusItemController: StatusItemController
    @StateObject private var limitsWindowPresenter: LimitsWindowPresenter

    @MainActor
    init() {
        let viewModel = LimitViewModel()
        let updateController = AppUpdateController()
        let settingsWindowPresenter = SettingsWindowPresenter()
        let releaseNotesWindowPresenter = ReleaseNotesWindowPresenter()
        let limitsWindowPresenter = LimitsWindowPresenter()
        let statusItemController = StatusItemController(
            viewModel: viewModel,
            updateController: updateController,
            settingsWindowPresenter: settingsWindowPresenter,
            limitsWindowPresenter: limitsWindowPresenter
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _updateController = StateObject(wrappedValue: updateController)
        _settingsWindowPresenter = StateObject(wrappedValue: settingsWindowPresenter)
        _releaseNotesWindowPresenter = StateObject(wrappedValue: releaseNotesWindowPresenter)
        _statusItemController = StateObject(wrappedValue: statusItemController)
        _limitsWindowPresenter = StateObject(wrappedValue: limitsWindowPresenter)
        appDelegate.showSettings = { focus in
            settingsWindowPresenter.show(viewModel: viewModel, updateController: updateController, focus: focus)
        }
        appDelegate.showInitialWindow = {
            releaseNotesWindowPresenter.showIfNeeded(viewModel: viewModel, onDismiss: {})
        }
        appDelegate.retryReleaseNotes = {
            releaseNotesWindowPresenter.showIfNeeded(viewModel: viewModel, onDismiss: {})
        }
        appDelegate.releaseNotesArePending = {
            releaseNotesWindowPresenter.hasUnacknowledgedNotes
        }
        appDelegate.showLimitsDetails = {
            limitsWindowPresenter.show(viewModel: viewModel)
        }
        appDelegate.openCodex = {
            CodexAppLauncher.open()
        }
        appDelegate.widgetClickAction = {
            viewModel.preferences.widgetClickAction
        }
        statusItemController.retryReleaseNotes = {
            releaseNotesWindowPresenter.showIfNeeded(viewModel: viewModel, onDismiss: {})
        }
        updateController.start()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

enum SettingsFocus: Hashable {
    case general
    case updates
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var showSettings: ((SettingsFocus) -> Void)?
    var showInitialWindow: (() -> Void)?
    var retryReleaseNotes: (() -> Bool)?
    /// True while release notes for the running build still wait for "Got it".
    var releaseNotesArePending: (() -> Bool)?
    var showLimitsDetails: (() -> Void)?
    var openCodex: (() -> Void)?
    /// Supplies the saved "click on a widget" action so the legacy
    /// `codexlimitwidget://open` link used by older widget builds resolves to
    /// the same destination as the current extension.
    var widgetClickAction: (() -> WidgetClickAction)?
    private var isSettingsPresentationPending = false
    private var launchDate = Date()
    private var systemSettingsWindowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchDate = Date()
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        installAppleEventHandlers()
        observeSystemSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // A window restored before the observers were installed.
            for window in NSApp.windows {
                self?.closeIfSystemSettingsWindow(window)
            }
            self?.showInitialWindow?()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if retryReleaseNotes?() == true { return true }
        if !flag {
            requestSettingsPresentation(focus: .general, deferringToPendingReleaseNotes: true)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else {
            requestSettingsPresentation(focus: .general)
            return
        }
        handleDeepLink(url)
    }

    /// The SwiftUI `Settings` scene only exists because an `App` needs a
    /// scene; its window is empty. macOS restores it at launch or opens it on
    /// ⌘, — close it, and route ⌘, to the real settings window instead.
    private func observeSystemSettingsWindow() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        systemSettingsWindowObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    self?.closeIfSystemSettingsWindow(window)
                }
            }
        }
    }

    private func closeIfSystemSettingsWindow(_ window: NSWindow) {
        let isSystemSettingsWindow = [window.identifier?.rawValue, window.frameAutosaveName]
            .contains { $0?.contains("SwiftUI_Settings") == true }
        guard window.isVisible, !(window is CustomSettingsWindow), isSystemSettingsWindow else { return }

        window.orderOut(nil)
        window.close()

        // Right after launch this is a restored window nobody asked for.
        if Date().timeIntervalSince(launchDate) > 3 {
            requestSettingsPresentation(focus: .general)
        }
    }

    private func installAppleEventHandlers() {
        let eventManager = NSAppleEventManager.shared()
        eventManager.setEventHandler(
            self,
            andSelector: #selector(handleOpenApplicationEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
        eventManager.setEventHandler(
            self,
            andSelector: #selector(handleOpenApplicationEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )
        eventManager.setEventHandler(
            self,
            andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleOpenApplicationEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        DispatchQueue.main.async { [weak self] in
            self?.requestSettingsPresentation(focus: .general, deferringToPendingReleaseNotes: true)
        }
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let urlString, let url = URL(string: urlString) else {
                self.requestSettingsPresentation(focus: .general)
                return
            }
            self.handleDeepLink(url)
        }
    }

    /// Widget and external links use `codexlimitwidget://<host>`:
    /// `open` (default app behaviour), `details` (detailed limits window) and `codex`.
    private func handleDeepLink(_ url: URL) {
        switch url.host?.lowercased() {
        case "details", "limits":
            requestLimitsDetailsPresentation()
        case "codex":
            openCodex?()
        default:
            performWidgetClickAction()
        }
    }

    /// Older widget builds always opened `codexlimitwidget://open` and a
    /// process that is still running the previous build keeps doing so after
    /// an update. Routing that host through the saved preference makes the
    /// already-installed extension behave like the current one.
    private func performWidgetClickAction() {
        switch widgetClickAction?() ?? .app {
        case .app:
            requestSettingsPresentation(focus: .general)
        case .details:
            requestLimitsDetailsPresentation()
        case .codex:
            openCodex?()
        }
    }

    private func requestLimitsDetailsPresentation() {
        guard !isSettingsPresentationPending else { return }
        isSettingsPresentationPending = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.isSettingsPresentationPending = false
            self.showLimitsDetails?()
        }
    }

    private func requestSettingsPresentation(
        focus: SettingsFocus,
        deferringToPendingReleaseNotes: Bool = false
    ) {
        // Launching or reactivating the app asks for Settings, which would
        // otherwise appear a moment after the update notes and cover them.
        if deferringToPendingReleaseNotes, releaseNotesArePending?() == true {
            _ = retryReleaseNotes?()
            return
        }

        guard !isSettingsPresentationPending else { return }
        isSettingsPresentationPending = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.isSettingsPresentationPending = false
            self.showSettings?(focus)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let shouldOpenUpdates = (response.notification.request.content.userInfo["codexLimitWidgetAction"] as? String) == "openUpdates"
        Task { @MainActor [weak self] in
            if shouldOpenUpdates {
                self?.requestSettingsPresentation(focus: .updates)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Codex desktop app

enum CodexAppLauncher {
    /// Bundle identifiers of the desktop app that ships Codex, most specific first.
    static let bundleIdentifiers = [
        "com.openai.codex",
        "com.openai.chat",
        "com.openai.chatgpt"
    ]

    static let webFallbackURL = URL(string: "https://chatgpt.com/codex")!

    @MainActor
    static func open() {
        let workspace = NSWorkspace.shared

        for identifier in bundleIdentifiers {
            guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: identifier) else {
                continue
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // AppKit calls this handler on its own LaunchServices queue. The
            // `@Sendable` annotation keeps the closure from inheriting the
            // main actor, which made the release build trap on that queue.
            workspace.openApplication(at: applicationURL, configuration: configuration) { @Sendable _, _ in }
            return
        }

        // No desktop app installed: fall back to the Codex web entry point.
        workspace.open(webFallbackURL)
    }
}

// MARK: - Status clipboard

@MainActor
enum StatusClipboard {
    static func statusText(for viewModel: LimitViewModel) -> String {
        if let snapshot = viewModel.snapshot {
            return snapshot.statusText(locale: viewModel.preferences.appLanguage.locale)
        }
        return viewModel.connectionStateTitle
    }

    @discardableResult
    static func copy(from viewModel: LimitViewModel) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(statusText(for: viewModel), forType: .string)
    }
}

// MARK: - Global hot key

private func codexLimitHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    controller.fire()
    return noErr
}

@MainActor
final class GlobalHotKeyController {
    private static let signature: OSType = 0x434C_4B57 // 'CLKW'
    private static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    func update(shortcut: HotkeyShortcut?, action: @escaping () -> Void) {
        self.action = action
        unregister()

        guard let shortcut, HotKeyShortcutFormatting.isValid(shortcut) else { return }
        installEventHandlerIfNeeded()
        register(shortcut)
    }

    func invalidate() {
        unregister()
        action = nil

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    nonisolated fileprivate func fire() {
        Task { @MainActor [weak self] in
            self?.action?()
        }
    }

    private func register(_ shortcut: HotkeyShortcut) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            HotKeyShortcutFormatting.carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        hotKeyRef = status == noErr ? reference : nil
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            codexLimitHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}

enum HotKeyShortcutFormatting {
    static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static func isValid(_ shortcut: HotkeyShortcut) -> Bool {
        !normalizedModifiers(shortcut.modifiers).isEmpty
    }

    static func normalizedModifiers(_ rawValue: Int) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(rawValue)).intersection(modifierMask)
    }

    static func carbonModifiers(for rawValue: Int) -> UInt32 {
        let flags = normalizedModifiers(rawValue)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func displayString(for shortcut: HotkeyShortcut?) -> String {
        guard let shortcut, isValid(shortcut) else { return "Not set" }

        var text = ""
        let flags = normalizedModifiers(shortcut.modifiers)
        if flags.contains(.control) { text += "\u{2303}" }
        if flags.contains(.option) { text += "\u{2325}" }
        if flags.contains(.shift) { text += "\u{21E7}" }
        if flags.contains(.command) { text += "\u{2318}" }
        return text.isEmpty ? keyName(for: shortcut.keyCode) : "\(text) \(keyName(for: shortcut.keyCode))"
    }

    static func keyName(for keyCode: Int) -> String {
        if let name = keyNames[keyCode] { return name }
        return "Key \(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "Left", 124: "Right",
        125: "Down", 126: "Up"
    ]
}

struct HotKeyRecorderControl: View {
    @ObservedObject var viewModel: LimitViewModel
    let palette: SettingsWindowPalette
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(
                    isRecording
                        ? LocalizedStringKey("Press keys")
                        : LocalizedStringKey(HotKeyShortcutFormatting.displayString(for: viewModel.preferences.hotkeyShortcut))
                )
                    .font(palette.controlFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 128, minHeight: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.backgroundHighlight)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isRecording ? palette.accent : palette.rule, lineWidth: isRecording ? 1.5 : 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Global shortcut")

            if viewModel.preferences.hotkeyShortcut != nil {
                Button {
                    stopRecording()
                    viewModel.updatePreferences { $0.hotkeyShortcut = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.backgroundHighlight)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(palette.rule, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear global shortcut")
            }
        }
        .disabled(!viewModel.preferences.hotkeyEnabled)
        .opacity(viewModel.preferences.hotkeyEnabled ? 1 : 0.45)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak viewModel] event in
            guard let viewModel else { return event }

            // Escape cancels recording; everything else must carry a modifier.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(HotKeyShortcutFormatting.modifierMask)
            guard !flags.isEmpty else { return nil }

            let shortcut = HotkeyShortcut(keyCode: Int(event.keyCode), modifiers: Int(flags.rawValue))
            viewModel.updatePreferences { preferences in
                preferences.hotkeyShortcut = shortcut
                preferences.hotkeyEnabled = true
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
