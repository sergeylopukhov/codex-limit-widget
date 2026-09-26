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

struct AppSettingsView: View {
    @ObservedObject var viewModel: LimitViewModel
    @ObservedObject var updateController: AppUpdateController
    let focus: SettingsFocus
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsCLIInstallConfirmation = false
    @State private var showsResetConfirmation = false
    @State private var isResettingAppData = false

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

                        SettingsRow("Left click", palette: palette) {
                            SettingsSegmentedControl(
                                selection: binding(\.menuBarLeftClickAction),
                                items: MenuBarClickAction.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                                palette: palette
                            )
                            .disabled(!viewModel.preferences.showsMenuBarItem)
                            .opacity(viewModel.preferences.showsMenuBarItem ? 1 : 0.45)
                        }

                        SettingsRow("Right click", palette: palette) {
                            SettingsSegmentedControl(
                                selection: binding(\.menuBarRightClickAction),
                                items: MenuBarRightClickAction.allCases.map { SettingsSegmentedItem(value: $0, title: $0.title) },
                                palette: palette
                            )
                            .disabled(!viewModel.preferences.showsMenuBarItem)
                            .opacity(viewModel.preferences.showsMenuBarItem ? 1 : 0.45)
                        }

                        Text("Widgets keep refreshing while the app is running, even when the menu bar item is hidden.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    SettingsRule(palette: palette)

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

                        Text("The widget opens the app, the detailed limits window, or Codex when you click it.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsRule(palette: palette)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionTitle("Global shortcut", palette: palette)

                        SettingsRow("Detailed limits window", palette: palette) {
                            SettingsSwitch(isOn: binding(\.hotkeyEnabled), palette: palette)
                        }

                        SettingsRow("Shortcut", palette: palette) {
                            HotKeyRecorderControl(viewModel: viewModel, palette: palette)
                        }

                        Text("Pick a combination with at least one modifier key. The shortcut brings the detailed limits window to the front from any app.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsRule(palette: palette)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionTitle("Quiet hours", palette: palette)

                        SettingsRow("Mute low limit alerts", palette: palette) {
                            SettingsSwitch(isOn: binding(\.quietHoursEnabled), palette: palette)
                        }

                        SettingsRow("From", palette: palette) {
                            SettingsTimePicker(minutes: binding(\.quietHoursStartMinutes), palette: palette)
                                .disabled(!viewModel.preferences.quietHoursEnabled)
                                .opacity(viewModel.preferences.quietHoursEnabled ? 1 : 0.45)
                        }

                        SettingsRow("To", palette: palette) {
                            SettingsTimePicker(minutes: binding(\.quietHoursEndMinutes), palette: palette)
                                .disabled(!viewModel.preferences.quietHoursEnabled)
                                .opacity(viewModel.preferences.quietHoursEnabled ? 1 : 0.45)
                        }

                        Text("Low limit alerts are not delivered during quiet hours, including windows that cross midnight. Quiet hours do not mute restoration notifications.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
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

                        Text("The 5-hour and weekly limits each have their own switch and thresholds. An alert is sent once for the nearest reached threshold; lower thresholds alert later if the limit continues to fall.")
                            .font(palette.noteFont)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsRule(palette: palette)

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

                        HStack(spacing: 12) {
                            SettingsActionButton(
                                title: viewModel.isRefreshing ? "Refreshing" : "Refresh now",
                                systemImage: "arrow.clockwise",
                                isDisabled: viewModel.isRefreshing,
                                palette: palette
                            ) {
                                Task { await viewModel.refresh(userInitiated: true) }
                            }

                            Spacer(minLength: 0)
                        }
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
                            Task { await viewModel.refresh(userInitiated: true) }
                        }
                    }

                    SettingsRule(palette: palette)

                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsSectionTitle("App data", palette: palette)
                            Text("Reset removes the stored limit snapshot, low limit notification history, and app settings. Your Codex account and CLI sign-in stay untouched.")
                                .font(palette.noteFont)
                                .foregroundStyle(palette.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
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

/// Row label and note copy for one low-limit alert window.
