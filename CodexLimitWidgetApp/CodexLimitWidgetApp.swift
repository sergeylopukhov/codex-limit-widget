import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

@main
struct CodexLimitWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: LimitViewModel
    @StateObject private var settingsWindowPresenter: SettingsWindowPresenter
    @StateObject private var statusItemController: StatusItemController

    @MainActor
    init() {
        let viewModel = LimitViewModel()
        let settingsWindowPresenter = SettingsWindowPresenter()
        let statusItemController = StatusItemController(
            viewModel: viewModel,
            settingsWindowPresenter: settingsWindowPresenter
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _settingsWindowPresenter = StateObject(wrappedValue: settingsWindowPresenter)
        _statusItemController = StateObject(wrappedValue: statusItemController)
        appDelegate.showSettings = {
            settingsWindowPresenter.show(viewModel: viewModel)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            settingsWindowPresenter.show(viewModel: viewModel)
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
    @ObservedObject var settingsWindowPresenter: SettingsWindowPresenter
    var close: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            SnapshotDetailView(
                snapshot: viewModel.snapshot,
                isRefreshing: viewModel.isRefreshing,
                refresh: { Task { await viewModel.refresh() } }
            )

            Divider()

            Button {
                close()
                DispatchQueue.main.async {
                    settingsWindowPresenter.show(viewModel: viewModel)
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.52, green: 0.95, blue: 0.43))
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.top, 9)

            Color.clear
                .frame(height: 14)
        }
        .frame(width: 286, alignment: .top)
        .background(Color(red: 0.02, green: 0.025, blue: 0.022))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.52, green: 0.95, blue: 0.43).opacity(0.22), lineWidth: 1)
        )
    }
}

@MainActor
final class StatusItemController: NSObject, ObservableObject, NSPopoverDelegate {
    private let viewModel: LimitViewModel
    private let settingsWindowPresenter: SettingsWindowPresenter
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: LimitViewModel, settingsWindowPresenter: SettingsWindowPresenter) {
        self.viewModel = viewModel
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
        button.toolTip = "Codex Limit Widget"
        button.setAccessibilityLabel("Codex Limit Widget")
        button.setAccessibilityValue(viewModel.menuBarTitle)

        switch viewModel.preferences.menuBarMode {
        case .percentOnly:
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.image = MenuBarPercentImageRenderer.image(percent: viewModel.compactMenuBarPercent)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            statusItem?.length = MenuBarPercentImageRenderer.size.width
        case .detailed:
            button.image = nil
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: viewModel.menuBarTitle,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.controlTextColor
                ]
            )
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

        let size = NSSize(width: 286, height: 244)
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
        Image(nsImage: MenuBarPercentImageRenderer.image(percent: percent))
            .renderingMode(.original)
            .resizable()
            .frame(
                width: MenuBarPercentImageRenderer.size.width,
                height: MenuBarPercentImageRenderer.size.height
            )
            .id(percent)
    }
}

private enum MenuBarPercentImageRenderer {
    static let size = NSSize(width: 30, height: 18)

    static func image(percent: Int) -> NSImage {
        let clampedPercent = max(0, min(100, percent))
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let text = "\(clampedPercent)%" as NSString
        text.draw(
            in: NSRect(x: 0, y: 6, width: size.width, height: 10),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )

        let trackRect = NSRect(x: 1, y: 2.5, width: size.width - 2, height: 2)
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

        image.isTemplate = true
        return image
    }
}

@MainActor
final class SettingsWindowPresenter: ObservableObject {
    private var windowController: NSWindowController?

    func show(viewModel: LimitViewModel) {
        let contentView = AppSettingsView(viewModel: viewModel)

        if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: contentView)
            window.center()
            bringToFront(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Limit Widget Settings"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.minSize = NSSize(width: 460, height: 360)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Application")
                        .font(.headline)

                    Toggle("Show menu bar item", isOn: binding(\.showsMenuBarItem))
                        .toggleStyle(.switch)

                    Picker("Menu bar", selection: binding(\.menuBarMode)) {
                        ForEach(MenuBarMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!viewModel.preferences.showsMenuBarItem)

                    Picker("Percent source", selection: binding(\.compactMenuBarMetric)) {
                        ForEach(MenuBarCompactMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!viewModel.preferences.showsMenuBarItem)

                    Text("Widgets keep refreshing while the app is running, even when the menu bar item is hidden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Widget")
                        .font(.headline)

                    Toggle("Show 5-hour limit", isOn: binding(\.widgetShowsFiveHour))
                        .toggleStyle(.switch)
                    Toggle("Show weekly limit", isOn: binding(\.widgetShowsWeekly))
                        .toggleStyle(.switch)
                    Toggle("Show reset time", isOn: binding(\.widgetShowsResetTimes))
                        .toggleStyle(.switch)
                    Toggle("Show last updated time", isOn: binding(\.widgetShowsLastUpdated))
                        .toggleStyle(.switch)
                    Toggle("Show stale warning", isOn: binding(\.widgetShowsStaleWarning))
                        .toggleStyle(.switch)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Auto refresh")
                            .font(.headline)
                        Text("Runs every minute while the app is open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh now") {
                        Task { await viewModel.refresh() }
                    }
                    .disabled(viewModel.isRefreshing)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 440, alignment: .topLeading)
        }
        .frame(minWidth: 440, minHeight: 360, alignment: .topLeading)
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
}
