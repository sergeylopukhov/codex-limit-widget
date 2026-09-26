import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
@preconcurrency import UserNotifications

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
                showsCopyStatus: true,
                onCopyStatus: { StatusClipboard.copy(from: viewModel) },
                showsLastUpdated: viewModel.preferences.widgetShowsLastUpdated,
                refresh: { Task { await viewModel.refresh(userInitiated: true) } }
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
    private let limitsWindowPresenter: LimitsWindowPresenter
    private let hotKeyController = GlobalHotKeyController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Called on every status-item click so update notes that were never
    /// acknowledged get another chance to appear while the user is actively
    /// working with the app. Returns true while unacknowledged notes are on
    /// screen, so that click is not also spent on the popover or Settings.
    var retryReleaseNotes: (() -> Bool)?

    init(
        viewModel: LimitViewModel,
        updateController: AppUpdateController,
        settingsWindowPresenter: SettingsWindowPresenter,
        limitsWindowPresenter: LimitsWindowPresenter
    ) {
        self.viewModel = viewModel
        self.updateController = updateController
        self.settingsWindowPresenter = settingsWindowPresenter
        self.limitsWindowPresenter = limitsWindowPresenter
        super.init()

        viewModel.$preferences
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.syncStatusItem()
                    self?.syncHotKey()
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
        syncHotKey()
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
        button.action = #selector(handleStatusItemClick)
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
            button.image = MenuBarPercentImageRenderer.image(
                value: viewModel.compactMenuBarValue,
                hasUpdate: updateController.isUpdateAvailable
            )
            button.imageScaling = .scaleNone
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            // Without the refresh glyph the item keeps a single width, and the
            // length is written on every pass so a refresh starting or ending
            // cannot leave the click target stale.
            let percentWidth = MenuBarPercentImageRenderer.size(
                for: viewModel.compactMenuBarValue,
                hasUpdate: updateController.isUpdateAvailable
            ).width
            statusItem?.length = percentWidth
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

    @objc private func handleStatusItemClick() {
        // A click is the user interacting with the app, so it is the natural
        // moment to re-offer unacknowledged update notes. When they are
        // presented now the click is consumed, otherwise the popover or the
        // Settings window would cover them instantly.
        if retryReleaseNotes?() == true { return }

        switch NSApp.currentEvent?.type {
        case .rightMouseUp, .rightMouseDown:
            performRightClickAction()
        default:
            performLeftClickAction()
        }
    }

    private func performLeftClickAction() {
        perform(menuBarAction: viewModel.preferences.menuBarLeftClickAction)
    }

    /// The right-click action is independent of the left-click action.
    /// `MenuBarRightClickAction.menu` keeps the built-in context menu; the
    /// other cases reuse the left-click routing.
    private func performRightClickAction() {
        guard let action = viewModel.preferences.menuBarRightClickAction.clickAction else {
            showContextMenu()
            return
        }

        perform(menuBarAction: action)
    }

    private func perform(menuBarAction action: MenuBarClickAction) {
        switch action {
        case .popover:
            togglePopover()
        case .settings:
            closePopover()
            settingsWindowPresenter.show(viewModel: viewModel, updateController: updateController)
        case .codex:
            closePopover()
            CodexAppLauncher.open()
        }
    }

    @objc private func togglePopover() {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            closePopover()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let refreshItem = NSMenuItem(
            title: viewModel.isRefreshing
                ? NSLocalizedString("Refreshing…", comment: "Menu bar refresh item while limits load")
                : NSLocalizedString("Refresh limits", comment: "Menu bar refresh item"),
            action: #selector(refreshFromMenu),
            keyEquivalent: ""
        )
        refreshItem.target = self
        refreshItem.isEnabled = !viewModel.isRefreshing
        menu.addItem(refreshItem)

        let copyItem = NSMenuItem(
            title: NSLocalizedString("Copy status", comment: "Menu bar copy status item"),
            action: #selector(copyStatusFromMenu),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.isEnabled = viewModel.snapshot != nil
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: NSLocalizedString("Quit", comment: "Menu bar quit item"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 6), in: button)
    }

    @objc private func refreshFromMenu() {
        Task { await viewModel.refresh(userInitiated: true) }
    }

    @objc private func copyStatusFromMenu() {
        StatusClipboard.copy(from: viewModel)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func syncHotKey() {
        let preferences = viewModel.preferences
        guard preferences.hotkeyEnabled else {
            hotKeyController.update(shortcut: nil, action: {})
            return
        }

        hotKeyController.update(shortcut: preferences.hotkeyShortcut) { [weak self] in
            guard let self else { return }
            self.limitsWindowPresenter.show(
                viewModel: self.viewModel
            )
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
                .foregroundColor: NSColor.black,
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
            image.isTemplate = true
            return image
        }

        let trackRect = NSRect(x: 1, y: 2.5, width: meterWidth - 2, height: 2)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 1.25, yRadius: 1.25)
        NSColor.black.withAlphaComponent(0.28).setFill()
        track.fill()

        let fillWidth = trackRect.width * CGFloat(clampedPercent) / 100
        if fillWidth > 0 {
            let fill = NSBezierPath(
                roundedRect: NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height),
                xRadius: 1.25,
                yRadius: 1.25
            )
            NSColor.black.setFill()
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

        image.isTemplate = true
        return image
    }
}
