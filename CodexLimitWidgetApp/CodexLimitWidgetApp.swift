import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

@main
struct CodexLimitWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: LimitViewModel
    @StateObject private var updateController: AppUpdateController
    @StateObject private var settingsWindowPresenter: SettingsWindowPresenter
    @StateObject private var statusItemController: StatusItemController

    @MainActor
    init() {
        let viewModel = LimitViewModel()
        let updateController = AppUpdateController()
        let settingsWindowPresenter = SettingsWindowPresenter()
        let statusItemController = StatusItemController(
            viewModel: viewModel,
            updateController: updateController,
            settingsWindowPresenter: settingsWindowPresenter
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _updateController = StateObject(wrappedValue: updateController)
        _settingsWindowPresenter = StateObject(wrappedValue: settingsWindowPresenter)
        _statusItemController = StateObject(wrappedValue: statusItemController)
        appDelegate.showSettings = {
            settingsWindowPresenter.show(viewModel: viewModel, updateController: updateController)
        }
        Task { @MainActor in
            updateController.start()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            settingsWindowPresenter.show(viewModel: viewModel, updateController: updateController)
        }
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
    var close: () -> Void = {}

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign

        VStack(spacing: 0) {
            SnapshotDetailView(
                snapshot: viewModel.snapshot,
                isRefreshing: viewModel.isRefreshing,
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

            Button(updateController.isBusy ? "Wait" : "Update") {
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
                percent: viewModel.compactMenuBarPercent,
                hasUpdate: updateController.isUpdateAvailable
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            statusItem?.length = MenuBarPercentImageRenderer.size(hasUpdate: updateController.isUpdateAvailable).width
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
        NSSize(width: 286, height: updateController.isUpdateAvailable ? 334 : 272)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var showSettings: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installAppleEventHandlers()
        showSettingsSoon()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsSoon()
        return true
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
    }

    @objc private func handleOpenApplicationEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        DispatchQueue.main.async { [weak self] in
            self?.showSettingsSoon()
        }
    }

    private func showSettingsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showSettings?()
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
        NSSize(width: hasUpdate ? 40 : 30, height: 18)
    }

    static func image(percent: Int, hasUpdate: Bool) -> NSImage {
        let clampedPercent = max(0, min(100, percent))
        let size = size(hasUpdate: hasUpdate)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let meterWidth: CGFloat = 30
        let text = "\(clampedPercent)%" as NSString
        text.draw(
            in: NSRect(x: 0, y: 6, width: meterWidth, height: 10),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )

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
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: updateParagraph
                ]
            )
        }

        image.isTemplate = true
        return image
    }
}

@MainActor
private final class CustomSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SettingsWindowPresenter: ObservableObject {
    private var windowController: NSWindowController?

    func show(viewModel: LimitViewModel, updateController: AppUpdateController) {
        let contentView = AppSettingsView(viewModel: viewModel, updateController: updateController)

        if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: contentView)
            window.center()
            bringToFront(window)
            return
        }

        let window = CustomSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Limit Widget Settings"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.minSize = NSSize(width: 540, height: 460)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct AppSettingsView: View {
    @ObservedObject var viewModel: LimitViewModel
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign
        let palette = SettingsWindowPalette(design: design)

        VStack(spacing: 0) {
            SettingsTitleBar(design: design, palette: palette)

            Rectangle()
                .fill(palette.rule)
                .frame(height: 1)

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

                    SettingsRule(palette: palette)

                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsSectionTitle("Auto refresh", palette: palette)
                            Text("Runs every minute while the app is open.")
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
        }
        .frame(minWidth: 540, minHeight: 460, alignment: .topLeading)
        .background(SettingsWindowBackground(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
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

private struct SettingsWindowPalette {
    let design: MenuWindowDesign

    var background: Color {
        switch design {
        case .terminal:
            return Color(red: 0.02, green: 0.026, blue: 0.022)
        case .editorial:
            return MenuWindowVisuals.editorialPaper
        }
    }

    var backgroundHighlight: Color {
        switch design {
        case .terminal:
            return Color(red: 0.11, green: 0.14, blue: 0.10)
        case .editorial:
            return MenuWindowVisuals.editorialPaperLight
        }
    }

    var titleText: Color {
        switch design {
        case .terminal:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialInk
        }
    }

    var primaryText: Color {
        switch design {
        case .terminal:
            return Color(red: 0.69, green: 0.91, blue: 0.64)
        case .editorial:
            return MenuWindowVisuals.editorialInk
        }
    }

    var mutedText: Color {
        switch design {
        case .terminal:
            return Color(red: 0.44, green: 0.62, blue: 0.40)
        case .editorial:
            return MenuWindowVisuals.editorialMutedInk
        }
    }

    var accent: Color {
        switch design {
        case .terminal:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialFill
        }
    }

    var accentText: Color {
        switch design {
        case .terminal:
            return Color(red: 0.025, green: 0.035, blue: 0.025)
        case .editorial:
            return MenuWindowVisuals.editorialPaperLight
        }
    }

    var controlTrack: Color {
        switch design {
        case .terminal:
            return Color(red: 0.09, green: 0.12, blue: 0.085)
        case .editorial:
            return MenuWindowVisuals.editorialEmpty
        }
    }

    var controlSelected: Color {
        switch design {
        case .terminal:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialFill
        }
    }

    var rule: Color {
        switch design {
        case .terminal:
            return Color(red: 0.29, green: 0.48, blue: 0.25).opacity(0.58)
        case .editorial:
            return MenuWindowVisuals.editorialRule.opacity(0.72)
        }
    }

    var border: Color {
        switch design {
        case .terminal:
            return MenuWindowVisuals.terminalBorder
        case .editorial:
            return MenuWindowVisuals.editorialRule.opacity(0.54)
        }
    }

    var titleFont: Font {
        switch design {
        case .terminal:
            return .system(size: 21, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 24, weight: .regular, design: .serif)
        }
    }

    var sectionFont: Font {
        switch design {
        case .terminal:
            return .system(size: 16, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 19, weight: .semibold)
        }
    }

    var labelFont: Font {
        switch design {
        case .terminal:
            return .system(size: 13, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 16, weight: .medium)
        }
    }

    var controlFont: Font {
        switch design {
        case .terminal:
            return .system(size: 12, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 15, weight: .medium)
        }
    }

    var noteFont: Font {
        switch design {
        case .terminal:
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
        Text(title)
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
            Text(title)
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
            Text(title)
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
                Text(title)
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
