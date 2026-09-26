import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
@preconcurrency import UserNotifications

@MainActor
final class CustomSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SettingsWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    private let initialContentSize = NSSize(width: 860, height: 580)
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

        // Reopening keeps the window where the user left it.
        if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: contentView)
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
        window.minSize = NSSize(width: 820, height: 480)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // A regular window: other apps can cover it, and it stays on the
        // Space where it was opened.
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        for window in LowLimitAlertWindow.allCases {
            viewModel?.removeEmptyLowLimitThresholds(for: window)
        }
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

/// Settings categories shown in the sidebar of the settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case widgets
    case notifications
    case updates
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu bar"
        case .widgets: return "Widgets"
        case .notifications: return "Notifications"
        case .updates: return "Updates"
        case .diagnostics: return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .widgets: return "square.grid.2x2.fill"
        case .notifications: return "bell.fill"
        case .updates: return "arrow.down"
        case .diagnostics: return "waveform.path.ecg"
        }
    }

    init(focus: SettingsFocus) {
        switch focus {
        case .general: self = .general
        case .updates: self = .updates
        }
    }
}

struct AppSettingsView: View {
    @ObservedObject var viewModel: LimitViewModel
    @ObservedObject var updateController: AppUpdateController
    let focus: SettingsFocus
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab
    @State private var showsCLIInstallConfirmation = false
    @State private var showsResetConfirmation = false
    @State private var isResettingAppData = false

    init(
        viewModel: LimitViewModel,
        updateController: AppUpdateController,
        focus: SettingsFocus,
        close: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.updateController = updateController
        self.focus = focus
        self.close = close
        _selectedTab = State(initialValue: SettingsTab(focus: focus))
    }

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark)
        let palette = SettingsWindowPalette(design: design)

        VStack(spacing: 0) {
            SettingsTitleBar(design: design, palette: palette)

            Rectangle()
                .fill(palette.rule)
                .frame(height: 1)

            HStack(spacing: 0) {
                SettingsSidebar(selection: $selectedTab, palette: palette)
                    .frame(width: 214)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        tabContent(selectedTab, palette: palette)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 26)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(selectedTab)
            }
        }
        .frame(minWidth: 820, minHeight: 480, alignment: .topLeading)
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
        .alert("Reset local app data?", isPresented: $showsResetConfirmation) {
            Button("Reset", role: .destructive) {
                isResettingAppData = true
                Task {
                    await viewModel.resetLocalAppData()
                    isResettingAppData = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the stored limit snapshot, low limit notification history, and app settings. Codex CLI sign-in and your account are not affected.")
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: SettingsTab, palette: SettingsWindowPalette) -> some View {
        switch tab {
        case .general:
            generalSection(palette: palette)
            SettingsRule(palette: palette)
            shortcutSection(palette: palette)
        case .menuBar:
            menuBarSection(palette: palette)
        case .widgets:
            widgetSection(palette: palette)
        case .notifications:
            lowLimitAlertsSection(palette: palette)
            SettingsRule(palette: palette)
            quietHoursSection(palette: palette)
        case .updates:
            updatesSection(palette: palette)
        case .diagnostics:
            codexCLISection(palette: palette)
            SettingsRule(palette: palette)
            diagnosticsSection(palette: palette)
            SettingsRule(palette: palette)
            appDataSection(palette: palette)
        }
    }

    private func generalSection(palette: SettingsWindowPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Application", palette: palette)

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
        }
    }

    private func shortcutSection(palette: SettingsWindowPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Global shortcut", palette: palette)

            SettingsRow("Detailed limits window", palette: palette) {
                SettingsSwitch(isOn: binding(\.hotkeyEnabled), palette: palette)
            }

            SettingsRow("Shortcut", palette: palette) {
                HotKeyRecorderControl(viewModel: viewModel, palette: palette)
            }

            SettingsNote("Pick a combination with at least one modifier key. The shortcut opens the detailed limits window from any app and closes it when pressed again.", palette: palette)
        }
    }

    private func menuBarSection(palette: SettingsWindowPalette) -> some View {
        let menuBarEnabled = viewModel.preferences.showsMenuBarItem
        let colorOptionsEnabled = menuBarEnabled && viewModel.preferences.menuBarMode == .percentOnly

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Menu bar", palette: palette)

            SettingsRow("Show menu bar item", palette: palette) {
                SettingsSwitch(isOn: binding(\.showsMenuBarItem), palette: palette)
            }

            SettingsRow("Display mode", palette: palette) {
                SettingsSegmentedControl(
                    selection: binding(\.menuBarMode),
                    items: MenuBarMode.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                    palette: palette
                )
                .disabled(!menuBarEnabled)
                .opacity(menuBarEnabled ? 1 : 0.45)
            }

            SettingsRow("Colored meter", palette: palette) {
                SettingsSwitch(isOn: binding(\.menuBarColoredMeter), palette: palette)
                    .disabled(!colorOptionsEnabled)
                    .opacity(colorOptionsEnabled ? 1 : 0.45)
            }

            SettingsRow("Colored digits", palette: palette) {
                SettingsSwitch(isOn: binding(\.menuBarColoredDigits), palette: palette)
                    .disabled(!colorOptionsEnabled)
                    .opacity(colorOptionsEnabled ? 1 : 0.45)
            }

            if viewModel.availableCompactMenuBarMetrics.count > 1 {
                SettingsRow("Percent source", palette: palette) {
                    SettingsSegmentedControl(
                        selection: binding(\.compactMenuBarMetric),
                        items: viewModel.availableCompactMenuBarMetrics.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                        palette: palette
                    )
                    .disabled(!menuBarEnabled)
                    .opacity(menuBarEnabled ? 1 : 0.45)
                }
            }

            SettingsRow("Left click", palette: palette) {
                SettingsSegmentedControl(
                    selection: binding(\.menuBarLeftClickAction),
                    items: MenuBarClickAction.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                    palette: palette
                )
                .disabled(!menuBarEnabled)
                .opacity(menuBarEnabled ? 1 : 0.45)
            }

            SettingsRow("Right click", palette: palette) {
                SettingsSegmentedControl(
                    selection: binding(\.menuBarRightClickAction),
                    items: MenuBarRightClickAction.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                    palette: palette
                )
                .disabled(!menuBarEnabled)
                .opacity(menuBarEnabled ? 1 : 0.45)
            }

            SettingsNote("Colors work in the compact percent mode: the meter, the digits, or both shift from green to dark red as the limit runs out. Widgets keep refreshing while the app is running, even when the menu bar item is hidden.", palette: palette)
                .padding(.top, 2)
        }
    }

    private func widgetSection(palette: SettingsWindowPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Widget", palette: palette)

            SettingsRow("Last update time", palette: palette) {
                SettingsSwitch(isOn: binding(\.widgetShowsLastUpdated), palette: palette)
            }

            SettingsRow("Widget click", palette: palette) {
                SettingsSegmentedControl(
                    selection: binding(\.widgetClickAction),
                    items: WidgetClickAction.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                    palette: palette
                )
            }

            SettingsNote("The widget opens the app, the detailed limits window, or Codex when you click it.", palette: palette)
        }
    }

    private func lowLimitAlertsSection(palette: SettingsWindowPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Low limit alerts", palette: palette)

            ForEach(LowLimitAlertWindow.allCases) { window in
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(window.alertSwitchTitle, palette: palette) {
                        SettingsSwitch(
                            isOn: Binding(
                                get: { viewModel.lowLimitAlertsEnabled(for: window) },
                                set: { viewModel.setLowLimitAlertsEnabled($0, for: window) }
                            ),
                            palette: palette
                        )
                    }

                    NotificationThresholdEditor(
                        viewModel: viewModel,
                        window: window,
                        palette: palette
                    )
                }
            }

            SettingsNote("The 5-hour and weekly limits each have their own switch and thresholds. An alert is sent once for the nearest reached threshold; lower thresholds alert later if the limit continues to fall.", palette: palette)
        }
    }

    private func quietHoursSection(palette: SettingsWindowPalette) -> some View {
        let quietHoursEnabled = viewModel.preferences.quietHoursEnabled

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Quiet hours", palette: palette)

            SettingsRow("Mute low limit alerts", palette: palette) {
                SettingsSwitch(isOn: binding(\.quietHoursEnabled), palette: palette)
            }

            SettingsRow("From", palette: palette) {
                SettingsTimePicker(minutes: binding(\.quietHoursStartMinutes), palette: palette)
                    .disabled(!quietHoursEnabled)
                    .opacity(quietHoursEnabled ? 1 : 0.45)
            }

            SettingsRow("To", palette: palette) {
                SettingsTimePicker(minutes: binding(\.quietHoursEndMinutes), palette: palette)
                    .disabled(!quietHoursEnabled)
                    .opacity(quietHoursEnabled ? 1 : 0.45)
            }

            SettingsNote("Low limit alerts are not delivered during quiet hours, including windows that cross midnight. Quiet hours do not mute restoration notifications.", palette: palette)
        }
    }

    private func updatesSection(palette: SettingsWindowPalette) -> some View {
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
    }

    private func codexCLISection(palette: SettingsWindowPalette) -> some View {
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
    }

    private func diagnosticsSection(palette: SettingsWindowPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Diagnostics", palette: palette)

            SettingsRow("Source", palette: palette) {
                Text(viewModel.dataSourceDescription)
                    .font(palette.controlFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            SettingsRow("Last success", palette: palette) {
                Text(LocalizedStringKey(viewModel.lastSyncText ?? "Never"))
                    .font(palette.controlFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            SettingsRow("CLI error", palette: palette) {
                Text(LocalizedStringKey(viewModel.lastErrorText ?? "None"))
                    .font(palette.controlFont)
                    .foregroundStyle(viewModel.lastErrorText == nil ? palette.mutedText : Color(red: 0.92, green: 0.33, blue: 0.28))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .center, spacing: 18) {
                SettingsNote("Refreshes limit percentages, credits, and token data every minute while the app is open.", palette: palette)

                Spacer(minLength: 16)

                SettingsActionButton(
                    title: viewModel.isRefreshing ? "Refreshing" : "Refresh now",
                    systemImage: "arrow.clockwise",
                    isDisabled: viewModel.isRefreshing,
                    palette: palette
                ) {
                    Task { await viewModel.refresh(userInitiated: true) }
                }
            }
        }
    }

    private func appDataSection(palette: SettingsWindowPalette) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                SettingsSectionTitle("App data", palette: palette)
                SettingsNote("Reset removes the stored limit snapshot, low limit notification history, and app settings. Your Codex account and CLI sign-in stay untouched.", palette: palette)
            }

            Spacer(minLength: 16)

            SettingsActionButton(
                title: isResettingAppData ? "Resetting" : "Reset data",
                systemImage: "trash",
                isDisabled: isResettingAppData,
                palette: palette
            ) {
                showsResetConfirmation = true
            }
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

/// Row label and note copy for one low-limit alert window.
