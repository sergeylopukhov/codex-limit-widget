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

    @MainActor
    init() {
        let viewModel = LimitViewModel()
        let updateController = AppUpdateController()
        let settingsWindowPresenter = SettingsWindowPresenter()
        let releaseNotesWindowPresenter = ReleaseNotesWindowPresenter()
        let statusItemController = StatusItemController(
            viewModel: viewModel,
            updateController: updateController,
            settingsWindowPresenter: settingsWindowPresenter
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _updateController = StateObject(wrappedValue: updateController)
        _settingsWindowPresenter = StateObject(wrappedValue: settingsWindowPresenter)
        _releaseNotesWindowPresenter = StateObject(wrappedValue: releaseNotesWindowPresenter)
        _statusItemController = StateObject(wrappedValue: statusItemController)
        appDelegate.showSettings = { focus in
            settingsWindowPresenter.show(viewModel: viewModel, updateController: updateController, focus: focus)
        }
        appDelegate.showInitialWindow = {
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

struct MenuBarContentView: View {
    @ObservedObject var viewModel: LimitViewModel
    @ObservedObject var updateController: AppUpdateController
    @ObservedObject var settingsWindowPresenter: SettingsWindowPresenter
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsCLIInstallConfirmation = false
    var close: () -> Void = {}

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark)

        VStack(spacing: 0) {
            SnapshotDetailView(
                snapshot: viewModel.snapshot,
                isRefreshing: viewModel.isRefreshing,
                showsConnectionStatus: viewModel.showsConnectionStatus,
                connectionTitle: viewModel.connectionStateTitle,
                connectionDetail: viewModel.connectionStateDetail,
                connectionActionTitle: viewModel.connectionActionTitle,
                connectionActionIcon: viewModel.connectionActionIcon,
                isConnectionActionBusy: viewModel.isCodexActionBusy,
                connectionAction: handleConnectionAction,
                design: design,
                refresh: { Task { await viewModel.refresh() } }
            )

            Rectangle()
                .fill(MenuWindowVisuals.separator(for: design))
                .frame(height: 1)

            if updateController.isUpdateAvailable {
                MenuBarUpdateBanner(updateController: updateController, design: design)

                Rectangle()
                    .fill(MenuWindowVisuals.separator(for: design))
                    .frame(height: 1)
            }

            Button {
                close()
                DispatchQueue.main.async {
                    settingsWindowPresenter.show(viewModel: viewModel, updateController: updateController)
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(MenuWindowVisuals.settingsForeground(for: design))
            .font(MenuWindowVisuals.settingsFont(for: design))
            .padding(.horizontal, 14)
            .padding(.top, 9)

            Color.clear
                .frame(height: 14)
        }
        .frame(width: 286, alignment: .top)
        .background(MenuWindowVisuals.popoverBackground(for: design))
        .alert("Install Codex CLI", isPresented: $showsCLIInstallConfirmation) {
            Button("Install") {
                Task { await viewModel.installCLI() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The official Codex CLI installer will be downloaded and installed for this user in ~/.local/bin. No administrator password is required.")
        }
    }

    private func handleConnectionAction() {
        switch viewModel.connectionState {
        case .cliNotInstalled:
            showsCLIInstallConfirmation = true
        case .authenticationRequired:
            Task { await viewModel.authenticate() }
        default:
            break
        }
    }
}

private struct MenuBarUpdateBanner: View {
    @ObservedObject var updateController: AppUpdateController
    let design: MenuWindowDesign

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 17, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(updateController.menuStatusText ?? "Update available")
                    .font(MenuWindowVisuals.settingsFont(for: design))
                    .lineLimit(1)
                Text("Verified from GitHub Releases")
                    .font(.system(size: 9, weight: .medium, design: design == .terminal ? .monospaced : .default))
                    .opacity(0.72)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(updateController.menuActionTitle) {
                Task { await updateController.installAvailableUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(design == .terminal ? MenuWindowVisuals.terminalAccent : MenuWindowVisuals.editorialFill)
            .disabled(updateController.isBusy)
        }
        .foregroundStyle(MenuWindowVisuals.settingsForeground(for: design))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
final class StatusItemController: NSObject, ObservableObject, NSPopoverDelegate {
    private let viewModel: LimitViewModel
    private let updateController: AppUpdateController
    private let settingsWindowPresenter: SettingsWindowPresenter
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: LimitViewModel,
        updateController: AppUpdateController,
        settingsWindowPresenter: SettingsWindowPresenter
    ) {
        self.viewModel = viewModel
        self.updateController = updateController
        self.settingsWindowPresenter = settingsWindowPresenter
        super.init()

        viewModel.$preferences
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.syncStatusItem()
                }
            }
            .store(in: &cancellables)

        viewModel.$snapshot
            .sink { [weak self] _ in
                self?.syncStatusItem()
            }
            .store(in: &cancellables)

        viewModel.$isRefreshing
            .sink { [weak self] _ in
                self?.syncStatusItem()
            }
            .store(in: &cancellables)

        viewModel.$connectionState
            .sink { [weak self] _ in
                self?.syncStatusItem()
                self?.resizePopoverIfNeeded()
            }
            .store(in: &cancellables)

        updateController.$phase
            .combineLatest(updateController.$availableRelease)
            .sink { [weak self] _, _ in
                self?.updateButton()
                self?.resizePopoverIfNeeded()
            }
            .store(in: &cancellables)

        syncStatusItem()
    }

    private func syncStatusItem() {
        guard viewModel.preferences.showsMenuBarItem else {
            if let statusItem {
                closePopover()
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
        }

        updateButton()
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = updateController.availableRelease.map {
            "Codex Limit Widget — version \($0.version) available"
        } ?? "Codex Limit Widget"
        button.setAccessibilityLabel("Codex Limit Widget")
        button.setAccessibilityValue(
            updateController.isUpdateAvailable
                ? "\(viewModel.menuBarTitle), update available"
                : viewModel.menuBarTitle
        )

        switch viewModel.preferences.menuBarMode {
        case .percentOnly:
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.image = MenuBarPercentImageRenderer.image(
                value: viewModel.compactMenuBarValue,
                hasUpdate: updateController.isUpdateAvailable
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            statusItem?.length = MenuBarPercentImageRenderer.size(
                for: viewModel.compactMenuBarValue,
                hasUpdate: updateController.isUpdateAvailable
            ).width
        case .detailed:
            button.image = nil
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .noImage
            let title = NSMutableAttributedString(
                string: viewModel.menuBarTitle,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.controlTextColor
                ]
            )
            if updateController.isUpdateAvailable {
                title.append(NSAttributedString(
                    string: "  ↑",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                        .foregroundColor: NSColor.systemGreen
                    ]
                ))
            }
            button.attributedTitle = title
            statusItem?.length = NSStatusItem.variableLength
        }
    }

    @objc private func togglePopover() {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }

        let size = preferredPopoverSize
        let activePopover: NSPopover

        if let popover {
            activePopover = popover
        } else {
            let createdPopover = NSPopover()
            createdPopover.behavior = .applicationDefined
            createdPopover.animates = true
            createdPopover.contentSize = size
            createdPopover.delegate = self
            createdPopover.contentViewController = NSHostingController(
                rootView: MenuBarContentView(
                    viewModel: viewModel,
                    updateController: updateController,
                    settingsWindowPresenter: settingsWindowPresenter,
                    close: { [weak self] in self?.closePopover() }
                )
                .environment(\.locale, viewModel.preferences.appLanguage.locale)
            )
            popover = createdPopover
            activePopover = createdPopover
        }

        activePopover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        installEventMonitors()
    }

    private var preferredPopoverSize: NSSize {
        var height = updateController.isUpdateAvailable ? 334 : 272
        if viewModel.showsConnectionStatus {
            height += 82
        }
        return NSSize(width: 286, height: height)
    }

    private func resizePopoverIfNeeded() {
        popover?.contentSize = preferredPopoverSize
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard self.popover?.isShown == true else { return event }

                if event.window === self.popover?.contentViewController?.view.window {
                    return event
                }

                if let buttonWindow = self.statusItem?.button?.window, event.window === buttonWindow {
                    return event
                }

                self.closePopover()
                return event
            }
        }

        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.closePopover()
                }
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            removeEventMonitors()
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
    private var isSettingsPresentationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        installAppleEventHandlers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showInitialWindow?()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            requestSettingsPresentation(focus: .general)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        requestSettingsPresentation(focus: .general)
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
            self?.requestSettingsPresentation(focus: .general)
        }
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        DispatchQueue.main.async { [weak self] in
            self?.requestSettingsPresentation(focus: .general)
        }
    }

    private func requestSettingsPresentation(focus: SettingsFocus) {
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

enum ReleaseNotesPresentationPolicy {
    static func shouldShow(
        currentVersionIdentifier: String,
        lastShownVersionIdentifier: String?
    ) -> Bool {
        lastShownVersionIdentifier != currentVersionIdentifier
    }
}

@MainActor
final class ReleaseNotesWindowPresenter: ObservableObject {
    private let lastShownVersionKey = "lastReleaseNotesVersion"
    private var windowController: NSWindowController?

    @discardableResult
    func showIfNeeded(viewModel: LimitViewModel, onDismiss: @escaping () -> Void) -> Bool {
        let version = currentVersionIdentifier
        let defaults = UserDefaults.standard
        let lastShownVersion = defaults.string(forKey: lastShownVersionKey)

        guard ReleaseNotesPresentationPolicy.shouldShow(
            currentVersionIdentifier: version,
            lastShownVersionIdentifier: lastShownVersion
        )
        else { return false }

        show(
            viewModel: viewModel,
            previousVersion: lastShownVersion.flatMap { ReleaseNotesVersion($0) },
            onDismiss: onDismiss
        )
        defaults.set(version, forKey: lastShownVersionKey)
        return true
    }

    private func show(
        viewModel: LimitViewModel,
        previousVersion: ReleaseNotesVersion?,
        onDismiss: @escaping () -> Void
    ) {
        let window = CustomSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New"
        window.contentViewController = NSHostingController(
            rootView: ReleaseNotesView(
                viewModel: viewModel,
                previousVersion: previousVersion,
                dismiss: { [weak self] in
                    self?.windowController?.close()
                    DispatchQueue.main.async(execute: onDismiss)
                }
            )
            .environment(\.locale, viewModel.preferences.appLanguage.locale)
        )
        window.minSize = NSSize(width: 560, height: 620)
        window.maxSize = window.minSize
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        // The window is positioned on the following AppKit cycle, when the
        // actual target screen is known. Keep it hidden meanwhile so it never
        // visibly jumps from AppKit's default position.
        window.alphaValue = 0

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            centerReleaseNotesWindow(window)
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private var currentVersionIdentifier: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
}

private struct ReleaseNotesVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let versionPart = String(value.split(separator: " ", maxSplits: 1).first ?? Substring(value))
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let rawComponents = versionPart.split(separator: ".")
        let components = rawComponents.compactMap { Int($0) }
        guard !rawComponents.isEmpty, components.count == rawComponents.count else { return nil }
        self.components = components
    }

    static func < (lhs: ReleaseNotesVersion, rhs: ReleaseNotesVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

@MainActor
private func centerReleaseNotesWindow(_ window: NSWindow) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        window.center()
        return
    }

    let frame = screen.visibleFrame
    window.setFrameOrigin(
        NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        )
    )
}

@MainActor
private func centerWindowOnMainScreen(_ window: NSWindow) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        window.center()
        return
    }

    let frame = screen.visibleFrame
    window.setFrameOrigin(
        NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        )
    )
}

private struct ReleaseNotesView: View {
    @ObservedObject var viewModel: LimitViewModel
    let previousVersion: ReleaseNotesVersion?
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark)
        let palette = SettingsWindowPalette(design: design)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(palette.backgroundHighlight))

                VStack(alignment: .leading, spacing: 3) {
                    Text("What's new")
                        .font(palette.titleFont)
                        .foregroundStyle(palette.titleText)
                    Text("Codex Limit Widget v\(currentVersion)")
                        .font(palette.noteFont)
                        .foregroundStyle(palette.mutedText)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("What's new in v\(currentVersion)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(palette.backgroundHighlight))

                Text("Improvements")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(palette.backgroundHighlight))
            }
            .padding(.top, 14)

            SettingsRule(palette: palette)
                .padding(.vertical, 18)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleReleaseNotes) { note in
                        ReleaseNoteRow(icon: note.icon, title: note.title, detail: note.detail)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            .foregroundStyle(palette.primaryText)

            HStack {
                Spacer()
                SettingsActionButton(
                    title: "Got it",
                    systemImage: "checkmark",
                    isDisabled: false,
                    palette: palette,
                    action: dismiss
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 18)
        }
        .padding(30)
        .frame(width: 560, height: 620, alignment: .topLeading)
        .background(SettingsWindowBackground(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var visibleReleaseNotes: [ReleaseNoteItem] {
        let notes = allReleaseNotes
        guard let previousVersion else { return notes }

        let newNotes = notes.filter { note in
            guard let introducedIn = ReleaseNotesVersion(note.introducedIn) else { return true }
            return introducedIn > previousVersion
        }

        if !newNotes.isEmpty { return newNotes }

        return notes.filter { note in
            note.introducedIn == currentVersion
        }
    }

    private var allReleaseNotes: [ReleaseNoteItem] {
        [
            ReleaseNoteItem(
                id: "login-item-once",
                introducedIn: "1.2.302",
                icon: "checkmark.shield",
                title: "One-time Login Item setup",
                detail: "The app registers at login only during a clean installation; updates and restarts never register it again."
            ),
            ReleaseNoteItem(
                id: "widget-glass-background",
                introducedIn: "1.2.302",
                icon: "rectangle.on.rectangle.angled",
                title: "Adaptive glass widget background",
                detail: "Desktop widgets use the system glass appearance when macOS dims them behind another window."
            ),
            ReleaseNoteItem(
                id: "four-decimal-credit-balance",
                introducedIn: "1.2.302",
                icon: "textformat.123",
                title: "Mode-specific credit precision",
                detail: "Percent mode shows two fractional digits, such as 200.95T. Detailed mode keeps four, such as 200.9500T."
            ),
            ReleaseNoteItem(
                id: "reliable-update-checks",
                introducedIn: "1.2.301",
                icon: "hourglass.badge.checkmark",
                title: "Reliable update checks",
                detail: "Update checks stop after 20 seconds instead of staying on Checking forever."
            ),
            ReleaseNoteItem(
                id: "reliable-update-downloads",
                introducedIn: "1.2.301",
                icon: "arrow.down.doc",
                title: "Reliable update downloads",
                detail: "The updater retries a release ZIP with a fresh URL when a CDN cache serves an older asset."
            ),
            ReleaseNoteItem(
                id: "green-update-indicator",
                introducedIn: "1.2.301",
                icon: "arrow.up.right",
                title: "Green update indicator",
                detail: "The update arrow stays green in both percent and detailed menu-bar modes."
            ),
            ReleaseNoteItem(
                id: "update-notifications",
                introducedIn: "1.2.301",
                icon: "bell.badge",
                title: "Update notifications",
                detail: "A new-version notification opens Settings directly at Updates."
            ),
            ReleaseNoteItem(
                id: "notifications-first-launch",
                introducedIn: "1.2.301",
                icon: "bell.and.waves.left.and.right",
                title: "Notifications on first launch",
                detail: "The app asks for notification permission on first launch and enables system alerts when allowed."
            ),
            ReleaseNoteItem(
                id: "auto-refresh-explained",
                introducedIn: "1.2.301",
                icon: "arrow.clockwise.circle",
                title: "Clear auto-refresh description",
                detail: "Settings explains that auto-refresh updates limit percentages, credits, token data, and related values."
            ),
            ReleaseNoteItem(
                id: "release-page-flow",
                introducedIn: "1.2.301",
                icon: "safari",
                title: "Cleaner release-page flow",
                detail: "The Settings window closes before the release page opens."
            ),
            ReleaseNoteItem(
                id: "full-credit-balance",
                introducedIn: "1.2.301",
                icon: "textformat.123",
                title: "Full credit balance",
                detail: "Compact menu-bar credits keep the T suffix and enough width for values such as 200.95T."
            ),
            ReleaseNoteItem(
                id: "credit-balance",
                introducedIn: "1.2.253",
                icon: "creditcard",
                title: "Credit balance in the menu bar",
                detail: "When a Codex limit is exhausted, the menu bar shows the remaining balance as 250T or ∞T."
            ),
            ReleaseNoteItem(
                id: "credit-readable",
                introducedIn: "1.2.253",
                icon: "textformat.size",
                title: "Readable compact balance",
                detail: "Credit values use the full menu-bar height and no longer leave space for the percentage meter."
            ),
            ReleaseNoteItem(
                id: "version-aware-notes",
                introducedIn: "1.2.253",
                icon: "clock.arrow.circlepath",
                title: "Version-aware update notes",
                detail: "Updates from 1.2.251 show only the latest changes; older upgrades include the intermediate release notes."
            ),
            ReleaseNoteItem(
                id: "detailed-credit-balance",
                introducedIn: "1.2.253",
                icon: "textformat.123",
                title: "Consistent detailed credit display",
                detail: "Detailed mode keeps the credit balance without 5H or 7D labels and shows up to four fractional digits."
            ),
            ReleaseNoteItem(
                id: "pinned-release-notes-action",
                introducedIn: "1.2.253",
                icon: "pin.fill",
                title: "Pinned What's New action",
                detail: "Long update notes scroll inside the window while the Got it button stays pinned in the bottom-right corner."
            ),
            ReleaseNoteItem(
                id: "login-item",
                introducedIn: "1.2.251",
                icon: "checkmark.circle",
                title: "One login item",
                detail: "Only the installed release app can register at login; Debug and temporary copies stay out."
            ),
            ReleaseNoteItem(
                id: "release-notes",
                introducedIn: "1.2.251",
                icon: "sparkles",
                title: "Reliable update notes",
                detail: "The What's New window now opens after an update, including the upgrade from 1.2.25 to 1.2.251."
            ),
            ReleaseNoteItem(
                id: "cli-status",
                introducedIn: "1.2.25",
                icon: "terminal",
                title: "Codex CLI status",
                detail: "The app clearly shows whether Codex CLI is connected, needs authorization, or is not installed."
            ),
            ReleaseNoteItem(
                id: "authorize",
                introducedIn: "1.2.25",
                icon: "person.badge.key",
                title: "Authorize from the app",
                detail: "Start the normal ChatGPT browser sign-in with one click; the app does not read or store tokens."
            ),
            ReleaseNoteItem(
                id: "install-cli",
                introducedIn: "1.2.25",
                icon: "arrow.down.circle",
                title: "Install Codex CLI",
                detail: "Install the official CLI for this user in ~/.local/bin when ChatGPT Desktop is installed without the CLI."
            ),
            ReleaseNoteItem(
                id: "stale-data",
                introducedIn: "1.2.25",
                icon: "clock.badge.exclamationmark",
                title: "Stale data is marked",
                detail: "The last successful snapshot stays visible during errors, but stale percentages are not presented as current in the menu bar."
            ),
            ReleaseNoteItem(
                id: "safe-widgets",
                introducedIn: "1.2.25",
                icon: "checkmark.shield",
                title: "Safe widgets",
                detail: "Widgets never install or authorize CLI; clicking a widget opens the app."
            ),
            ReleaseNoteItem(
                id: "recovery-steps",
                introducedIn: "1.2.25",
                icon: "exclamationmark.bubble",
                title: "Clear recovery steps",
                detail: "Installation and login errors explain what happened and show the official manual command when needed."
            )
        ]
    }
}

private struct ReleaseNoteItem: Identifiable {
    let id: String
    let introducedIn: String
    let icon: String
    let title: String
    let detail: String
}

private struct ReleaseNoteRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .semibold))
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 12))
                    .opacity(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MenuBarPercentMeter: View {
    let percent: Int

    var body: some View {
        Image(nsImage: MenuBarPercentImageRenderer.image(percent: percent, hasUpdate: false))
            .renderingMode(.original)
            .resizable()
            .frame(
                width: MenuBarPercentImageRenderer.size(hasUpdate: false).width,
                height: MenuBarPercentImageRenderer.size(hasUpdate: false).height
            )
            .id(percent)
    }
}

private enum MenuBarPercentImageRenderer {
    static func size(hasUpdate: Bool) -> NSSize {
        size(for: "0%", hasUpdate: hasUpdate)
    }

    static func size(for value: String, hasUpdate: Bool) -> NSSize {
        let valueWidth = value.hasSuffix("%") ? 30 : creditValueWidth(for: value)
        return NSSize(width: valueWidth + (hasUpdate ? 10 : 0), height: 18)
    }

    private static func creditValueWidth(for value: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let measuredWidth = (value as NSString).size(withAttributes: [.font: font]).width
        return max(40, ceil(measuredWidth) + 4)
    }

    static func image(percent: Int, hasUpdate: Bool) -> NSImage {
        image(value: "\(max(0, min(100, percent)))%", hasUpdate: hasUpdate)
    }

    static func image(value: String, hasUpdate: Bool) -> NSImage {
        let isPercent = value.hasSuffix("%")
        let meterWidth: CGFloat = isPercent ? 30 : creditValueWidth(for: value)
        let clampedPercent = Int(value.dropLast()) ?? 0
        let size = size(for: value, hasUpdate: hasUpdate)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let text = value as NSString
        let textRect = isPercent
            ? NSRect(x: 0, y: 6, width: meterWidth, height: 10)
            : NSRect(x: 0, y: 1, width: meterWidth, height: 16)
        text.draw(
            in: textRect,
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: isPercent ? 9.5 : 13,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )

        guard isPercent else {
            if hasUpdate {
                let updateParagraph = NSMutableParagraphStyle()
                updateParagraph.alignment = .center
                ("↑" as NSString).draw(
                    in: NSRect(x: meterWidth, y: 3.5, width: 10, height: 14),
                    withAttributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                        .foregroundColor: NSColor.systemGreen,
                        .paragraphStyle: updateParagraph
                    ]
                )
            }
            image.isTemplate = false
            return image
        }

        let trackRect = NSRect(x: 1, y: 2.5, width: meterWidth - 2, height: 2)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 1.25, yRadius: 1.25)
        NSColor.white.withAlphaComponent(0.28).setFill()
        track.fill()

        let fillWidth = trackRect.width * CGFloat(clampedPercent) / 100
        if fillWidth > 0 {
            let fill = NSBezierPath(
                roundedRect: NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height),
                xRadius: 1.25,
                yRadius: 1.25
            )
            NSColor.white.setFill()
            fill.fill()
        }

        if hasUpdate {
            let updateParagraph = NSMutableParagraphStyle()
            updateParagraph.alignment = .center
            ("↑" as NSString).draw(
                in: NSRect(x: 30, y: 3.5, width: 10, height: 14),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.systemGreen,
                    .paragraphStyle: updateParagraph
                ]
            )
        }

        image.isTemplate = false
        return image
    }
}

@MainActor
private final class CustomSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SettingsWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    private let initialContentSize = NSSize(width: 580, height: 520)
    private var windowController: NSWindowController?
    private weak var viewModel: LimitViewModel?

    func show(
        viewModel: LimitViewModel,
        updateController: AppUpdateController,
        focus: SettingsFocus = .general
    ) {
        self.viewModel = viewModel
        let contentView = LocalizedSettingsRoot(
            viewModel: viewModel,
            updateController: updateController,
            focus: focus,
            close: { [weak self] in self?.close() }
        )

        if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: contentView)
            centerOnMainScreen(window)
            bringToFront(window)
            return
        }

        let window = CustomSettingsWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Limit Widget Settings"
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: contentView)
        window.minSize = NSSize(width: 540, height: 460)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.alphaValue = 0

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            window.setContentSize(self.initialContentSize)
            self.centerOnMainScreen(window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.centerOnMainScreen(window)
                window.alphaValue = 1
                self.bringToFront(window)
            }
        }
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        windowController?.close()
    }

    private func centerOnMainScreen(_ window: NSWindow) {
        centerWindowOnMainScreen(window)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.removeEmptyNotificationThresholds()
    }
}

private struct LocalizedSettingsRoot: View {
    @ObservedObject var viewModel: LimitViewModel
    @ObservedObject var updateController: AppUpdateController
    let focus: SettingsFocus
    let close: () -> Void

    var body: some View {
        AppSettingsView(
            viewModel: viewModel,
            updateController: updateController,
            focus: focus,
            close: close
        )
            .environment(\.locale, viewModel.preferences.appLanguage.locale)
    }
}

struct AppSettingsView: View {
    @ObservedObject var viewModel: LimitViewModel
    @ObservedObject var updateController: AppUpdateController
    let focus: SettingsFocus
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsCLIInstallConfirmation = false

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark)
        let palette = SettingsWindowPalette(design: design)

        VStack(spacing: 0) {
            SettingsTitleBar(design: design, palette: palette)

            Rectangle()
                .fill(palette.rule)
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionTitle("Application", palette: palette)

                        SettingsRow("Show menu bar item", palette: palette) {
                            SettingsSwitch(isOn: binding(\.showsMenuBarItem), palette: palette)
                        }

                        SettingsRow("Window design", palette: palette) {
                            SettingsSegmentedControl(
                                selection: binding(\.menuWindowDesign),
                                items: MenuWindowDesign.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                                palette: palette
                            )
                        }

                        SettingsRow("Language", palette: palette) {
                            SettingsSegmentedControl(
                                selection: binding(\.appLanguage),
                                items: AppLanguage.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                                palette: palette
                            )
                        }

                        SettingsRow("Menu bar", palette: palette) {
                            SettingsSegmentedControl(
                                selection: binding(\.menuBarMode),
                                items: MenuBarMode.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                                palette: palette
                            )
                            .disabled(!viewModel.preferences.showsMenuBarItem)
                            .opacity(viewModel.preferences.showsMenuBarItem ? 1 : 0.45)
                        }

                        if viewModel.availableCompactMenuBarMetrics.count > 1 {
                            SettingsRow("Percent source", palette: palette) {
                                SettingsSegmentedControl(
                                    selection: binding(\.compactMenuBarMetric),
                                    items: viewModel.availableCompactMenuBarMetrics.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                                    palette: palette
                                )
                                .disabled(!viewModel.preferences.showsMenuBarItem)
                                .opacity(viewModel.preferences.showsMenuBarItem ? 1 : 0.45)
                            }
                        }

                        Text("Widgets keep refreshing while the app is running, even when the menu bar item is hidden.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    SettingsRule(palette: palette)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionTitle("Codex CLI", palette: palette)

                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(viewModel.connectionStateTitle))
                                    .font(palette.noteFont)
                                    .foregroundStyle(viewModel.connectionState == .ready ? palette.accent : palette.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let detail = viewModel.connectionStateDetail {
                                    Text(LocalizedStringKey(detail))
                                        .font(palette.noteFont)
                                        .foregroundStyle(palette.mutedText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 16)

                            if let actionTitle = viewModel.connectionActionTitle {
                                SettingsActionButton(
                                    title: actionTitle,
                                    systemImage: viewModel.connectionActionIcon,
                                    isDisabled: viewModel.isCodexActionBusy,
                                    palette: palette
                                ) {
                                    handleConnectionAction()
                                }
                            }
                        }
                    }

                    SettingsRule(palette: palette)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionTitle("Low limit alerts", palette: palette)

                        SettingsRow("System notifications", palette: palette) {
                            SettingsSwitch(
                                isOn: Binding(
                                    get: { viewModel.preferences.lowLimitNotificationsEnabled },
                                    set: { viewModel.setLowLimitNotificationsEnabled($0) }
                                ),
                                palette: palette
                            )
                        }

                        NotificationThresholdEditor(viewModel: viewModel, palette: palette)

                        Text("Alerts are sent once for the nearest reached threshold in each available limit window; lower thresholds alert later if the limit continues to fall.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsRule(palette: palette)

                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            SettingsSectionTitle("Updates", palette: palette)
                            Text(updateController.settingsStatusText)
                                .font(palette.noteFont)
                                .foregroundStyle(updateController.isUpdateAvailable ? palette.accent : palette.mutedText)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Installed: v\(updateController.currentVersion)")
                                .font(palette.noteFont)
                                .foregroundStyle(palette.mutedText)

                            if let errorMessage = updateController.errorMessage {
                                Text(errorMessage)
                                    .font(palette.noteFont)
                                    .foregroundStyle(Color(red: 0.92, green: 0.33, blue: 0.28))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if updateController.isUpdateAvailable {
                                Button("Open release page") {
                                    close()
                                    updateController.openReleasePage()
                                }
                                .buttonStyle(.plain)
                                .font(palette.noteFont)
                                .foregroundStyle(palette.accent)
                                .underline()
                            }
                        }

                        Spacer(minLength: 16)

                        SettingsActionButton(
                            title: updateActionTitle,
                            systemImage: updateActionIcon,
                            isDisabled: updateController.isBusy,
                            palette: palette
                        ) {
                            Task {
                                if updateController.isUpdateAvailable {
                                    await updateController.installAvailableUpdate()
                                } else {
                                    await updateController.checkForUpdates()
                                }
                            }
                        }
                    }
                    .id(SettingsFocus.updates)

                    SettingsRule(palette: palette)

                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsSectionTitle("Auto refresh", palette: palette)
                            Text("Refreshes limit percentages, credits, and token data every minute while the app is open.")
                                .font(palette.noteFont)
                                .foregroundStyle(palette.mutedText)
                        }
                        Spacer(minLength: 16)
                        SettingsActionButton(
                            title: viewModel.isRefreshing ? "Refreshing" : "Refresh now",
                            systemImage: "arrow.clockwise",
                            isDisabled: viewModel.isRefreshing,
                            palette: palette
                        ) {
                            Task { await viewModel.refresh() }
                        }
                    }

                    Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    guard focus == .updates else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(SettingsFocus.updates, anchor: .top)
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 460, alignment: .topLeading)
        .background(SettingsWindowBackground(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .alert("Install Codex CLI", isPresented: $showsCLIInstallConfirmation) {
            Button("Install") {
                Task { await viewModel.installCLI() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The official Codex CLI installer will be downloaded and installed for this user in ~/.local/bin. No administrator password is required.")
        }
    }

    private func handleConnectionAction() {
        switch viewModel.connectionState {
        case .cliNotInstalled:
            showsCLIInstallConfirmation = true
        case .authenticationRequired:
            Task { await viewModel.authenticate() }
        default:
            break
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LimitPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.preferences[keyPath: keyPath] },
            set: { newValue in
                viewModel.updatePreferences { preferences in
                    preferences[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var updateActionTitle: String {
        switch updateController.phase {
        case .checking:
            return "Checking"
        case .downloading:
            return "Downloading"
        case .installing:
            return "Installing"
        default:
            return updateController.isUpdateAvailable ? "Update now" : "Check now"
        }
    }

    private var updateActionIcon: String {
        updateController.isUpdateAvailable ? "arrow.down.circle" : "arrow.clockwise"
    }
}

private struct NotificationThresholdEditor: View {
    @ObservedObject var viewModel: LimitViewModel
    let palette: SettingsWindowPalette

    var body: some View {
        SettingsRow("Alert thresholds", palette: palette) {
            HStack(spacing: 6) {
                if canRemoveThreshold {
                    Button {
                        viewModel.removeLastNotificationThreshold()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
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
                    .accessibilityLabel("Remove last alert threshold")
                }

                ForEach(Array(viewModel.preferences.lowLimitNotificationThresholds.indices), id: \.self) { index in
                    SettingsThresholdField(
                        text: thresholdBinding(at: index),
                        palette: palette
                    )
                }

                if canAddThreshold {
                    Button {
                        viewModel.addNotificationThreshold()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
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
                    .accessibilityLabel("Add alert threshold")
                }
            }
        }
    }

    private var canAddThreshold: Bool {
        viewModel.preferences.lowLimitNotificationThresholds.count < 5
    }

    private var canRemoveThreshold: Bool {
        !viewModel.preferences.lowLimitNotificationThresholds.isEmpty
    }

    private func thresholdBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                let thresholds = viewModel.preferences.lowLimitNotificationThresholds
                return index < thresholds.count ? thresholds[index].map(String.init) ?? "" : ""
            },
            set: { value in
                var thresholds = viewModel.preferences.lowLimitNotificationThresholds.map { $0.map(String.init) ?? "" }
                while thresholds.count <= index { thresholds.append("") }
                thresholds[index] = value
                let values = thresholds.map { text in
                    text.isEmpty ? nil : Int(text)
                }
                viewModel.updatePreferences {
                    $0.lowLimitNotificationThresholds = LimitPreferences.normalizedNotificationThresholds(values)
                }
            }
        )
    }
}

private struct SettingsThresholdField: View {
    @Binding var text: String
    let palette: SettingsWindowPalette
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text("%").foregroundStyle(palette.mutedText)
        )
        .textFieldStyle(.plain)
        .font(palette.controlFont)
        .foregroundStyle(palette.primaryText)
        .multilineTextAlignment(.center)
        .focused($isFocused)
        .padding(.horizontal, 6)
        .frame(width: 42, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.backgroundHighlight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? palette.accent : palette.rule, lineWidth: isFocused ? 1.5 : 1)
        )
        .accessibilityLabel("Alert threshold")
    }
}

private struct SettingsWindowPalette {
    let design: MenuWindowDesign

    var background: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.02, green: 0.026, blue: 0.022)
        case .editorial:
            return MenuWindowVisuals.editorialPaper
        }
    }

    var backgroundHighlight: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.11, green: 0.14, blue: 0.10)
        case .editorial:
            return MenuWindowVisuals.editorialPaperLight
        }
    }

    var titleText: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialInk
        }
    }

    var primaryText: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.69, green: 0.91, blue: 0.64)
        case .editorial:
            return MenuWindowVisuals.editorialInk
        }
    }

    var mutedText: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.44, green: 0.62, blue: 0.40)
        case .editorial:
            return MenuWindowVisuals.editorialMutedInk
        }
    }

    var accent: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialFill
        }
    }

    var accentText: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.025, green: 0.035, blue: 0.025)
        case .editorial:
            return MenuWindowVisuals.editorialPaperLight
        }
    }

    var controlTrack: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.09, green: 0.12, blue: 0.085)
        case .editorial:
            return MenuWindowVisuals.editorialEmpty
        }
    }

    var controlSelected: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialFill
        }
    }

    var rule: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.29, green: 0.48, blue: 0.25).opacity(0.58)
        case .editorial:
            return MenuWindowVisuals.editorialRule.opacity(0.72)
        }
    }

    var border: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalBorder
        case .editorial:
            return MenuWindowVisuals.editorialRule.opacity(0.54)
        }
    }

    var titleFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 21, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 24, weight: .regular, design: .serif)
        }
    }

    var sectionFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 16, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 19, weight: .semibold)
        }
    }

    var labelFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 13, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 16, weight: .medium)
        }
    }

    var controlFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 12, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 15, weight: .medium)
        }
    }

    var noteFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 11, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 13, weight: .regular)
        }
    }
}

private struct SettingsWindowBackground: View {
    let palette: SettingsWindowPalette

    var body: some View {
        ZStack {
            Rectangle()
                .fill(palette.background)

            LinearGradient(
                colors: [
                    palette.backgroundHighlight.opacity(0.92),
                    palette.background.opacity(0.78),
                    palette.accent.opacity(palette.design == .terminal ? 0.10 : 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SettingsTitleBar: View {
    let design: MenuWindowDesign
    let palette: SettingsWindowPalette
    @State private var showsWindowButtonSymbols = false

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                SettingsWindowButton(command: .close, showsSymbol: showsWindowButtonSymbols)
                SettingsWindowButton(command: .minimize, showsSymbol: showsWindowButtonSymbols)
                SettingsWindowButton(command: .zoom, showsSymbol: showsWindowButtonSymbols)
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    showsWindowButtonSymbols = isHovering
                }
            }

            Text("Codex Limit Widget Settings")
                .font(palette.titleFont)
                .foregroundStyle(palette.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 12)

            Text(design == .terminal ? "DARK" : "BEIGE")
                .font(palette.noteFont)
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .contentShape(Rectangle())
    }
}

private enum SettingsWindowCommand {
    case close
    case minimize
    case zoom

    var color: Color {
        switch self {
        case .close:
            return Color(red: 1.00, green: 0.32, blue: 0.34)
        case .minimize:
            return Color(red: 1.00, green: 0.74, blue: 0.06)
        case .zoom:
            return Color(red: 0.18, green: 0.78, blue: 0.32)
        }
    }

    var symbolName: String {
        switch self {
        case .close:
            return "xmark"
        case .minimize:
            return "minus"
        case .zoom:
            return "arrow.up.left.and.arrow.down.right"
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .close, .minimize:
            return 7.5
        case .zoom:
            return 6.5
        }
    }

    @MainActor
    func perform() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        switch self {
        case .close:
            window.close()
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.zoom(nil)
        }
    }
}

private struct SettingsWindowButton: View {
    let command: SettingsWindowCommand
    let showsSymbol: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            command.perform()
        } label: {
            ZStack {
                Circle()
                    .fill(command.color)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.6)
                    )

                Image(systemName: command.symbolName)
                    .font(.system(size: command.symbolSize, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(showsSymbol ? 1 : 0)
            }
            .frame(width: 13, height: 13)
            .scaleEffect(isHovering ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: showsSymbol)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct SettingsSectionTitle: View {
    let title: String
    let palette: SettingsWindowPalette

    init(_ title: String, palette: SettingsWindowPalette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(palette.sectionFont)
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let palette: SettingsWindowPalette
    @ViewBuilder let control: () -> Control

    init(_ title: String, palette: SettingsWindowPalette, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.palette = palette
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(LocalizedStringKey(title))
                .font(palette.labelFont)
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 14)

            control()
        }
        .frame(minHeight: 32)
    }
}

private struct SettingsRule: View {
    let palette: SettingsWindowPalette

    var body: some View {
        Rectangle()
            .fill(palette.rule)
            .frame(height: 1)
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    let palette: SettingsWindowPalette

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? palette.accent : palette.controlTrack)
                .frame(width: 54, height: 28)
                .overlay(
                    Circle()
                        .fill(isOn ? palette.accentText : palette.backgroundHighlight)
                        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                        .frame(width: 22, height: 22)
                        .offset(x: isOn ? 13 : -13)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(palette.rule.opacity(isOn ? 0.0 : 0.9), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct SettingsSegmentedItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

private struct SettingsSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [SettingsSegmentedItem<Value>]
    let palette: SettingsWindowPalette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = selection == item.value

                SettingsSegmentedOption(
                    title: item.title,
                    isSelected: isSelected,
                    palette: palette
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = item.value
                    }
                }
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(palette.controlTrack)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(palette.rule.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct SettingsSegmentedOption: View {
    let title: String
    let isSelected: Bool
    let palette: SettingsWindowPalette
    let action: () -> Void

    var body: some View {
        let foreground = isSelected ? palette.accentText : palette.primaryText
        let background = isSelected ? palette.controlSelected : Color.clear

        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(palette.controlFont)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 14)
                .frame(minWidth: 76)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let palette: SettingsWindowPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(LocalizedStringKey(title))
                    .font(palette.controlFont)
            }
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.accent.opacity(isDisabled ? 0.45 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
