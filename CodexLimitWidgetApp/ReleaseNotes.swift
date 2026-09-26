import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
@preconcurrency import UserNotifications

enum ReleaseNotesPresentationPolicy {
    static func shouldShow(
        currentVersionIdentifier: String,
        acknowledgedVersionIdentifier: String?
    ) -> Bool {
        acknowledgedVersionIdentifier != currentVersionIdentifier
    }

    /// Builds 1.2.400 and earlier wrote their marker while *showing* the
    /// window, so a marker they left behind does not prove the notes were
    /// read and can point at a version the user never saw. Stepping one patch
    /// version below that marker keeps its own notes inside the visible
    /// range, which is why the falsely marked 1.2.400 notes still appear in
    /// 1.2.401.
    static func unacknowledgedBaseline(forLegacyMarker marker: String) -> String? {
        guard let version = ReleaseNotesVersion(marker), !version.components.isEmpty else {
            return nil
        }

        var components = version.components
        let lastIndex = components.count - 1
        components[lastIndex] = components[lastIndex] > 0 ? components[lastIndex] - 1 : 0
        return components.map(String.init).joined(separator: ".")
    }
}

@MainActor
final class ReleaseNotesWindowPresenter: ObservableObject {
    private let acknowledgedVersionKey = "acknowledgedReleaseNotesVersion"
    /// Marker written by builds that recorded the version before the user
    /// confirmed with "Got it". Kept read-only for migration.
    private let legacyShownVersionKey = "lastReleaseNotesVersion"
    private var windowController: NSWindowController?

    @discardableResult
    func showIfNeeded(viewModel: LimitViewModel, onDismiss: @escaping () -> Void = {}) -> Bool {
        let version = currentVersionIdentifier
        let defaults = UserDefaults.standard
        let acknowledgedKey = acknowledgedVersionKey

        guard ReleaseNotesPresentationPolicy.shouldShow(
            currentVersionIdentifier: version,
            acknowledgedVersionIdentifier: defaults.string(forKey: acknowledgedKey)
        ) else { return false }

        // The notes stay pending until "Got it", so an interaction while they
        // are on screen brings them to the front again instead of burying
        // them under the popover or the Settings window.
        if let window = windowController?.window, window.isVisible {
            bringToFront(window)
            return true
        }

        show(viewModel: viewModel, previousVersion: pendingPreviousVersion) { [weak self] in
            // The version counts as read only once the user confirms with
            // "Got it", so an unnoticed window is offered again later.
            defaults.set(version, forKey: acknowledgedKey)
            self?.windowController = nil
            onDismiss()
        }

        // Only claim the interaction when the window really is on screen, so
        // a presentation that failed cannot swallow every menu-bar click.
        return windowController?.window?.isVisible == true
    }

    /// True while this build has notes the user has not confirmed with
    /// "Got it", whether or not the window is on screen right now.
    var hasUnacknowledgedNotes: Bool {
        ReleaseNotesPresentationPolicy.shouldShow(
            currentVersionIdentifier: currentVersionIdentifier,
            acknowledgedVersionIdentifier: UserDefaults.standard.string(forKey: acknowledgedVersionKey)
        )
    }

    /// Version that bounds the visible notes for this launch, or nil to show
    /// the full catalogue on a first run.
    private var pendingPreviousVersion: ReleaseNotesVersion? {
        let defaults = UserDefaults.standard

        if let acknowledged = defaults.string(forKey: acknowledgedVersionKey) {
            return ReleaseNotesVersion(acknowledged)
        }

        guard let legacy = defaults.string(forKey: legacyShownVersionKey),
              let baseline = ReleaseNotesPresentationPolicy.unacknowledgedBaseline(forLegacyMarker: legacy)
        else { return nil }

        return ReleaseNotesVersion(baseline)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
                    self?.windowController = nil
                    onDismiss()
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
func centerWindowOnMainScreen(_ window: NSWindow) {
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
                id: "settings-tabs",
                introducedIn: "1.3.0",
                icon: "slider.horizontal.3",
                title: "Settings in tabs",
                detail: "Settings are split into tabs: General, Menu bar, Widgets, Notifications, Updates, and Diagnostics. The window can be dragged anywhere and no longer stays above other apps."
            ),
            ReleaseNoteItem(
                id: "colored-menu-bar-meter",
                introducedIn: "1.3.0",
                icon: "paintpalette",
                title: "Colored menu bar meter",
                detail: "In percent mode the meter under the number goes from green at a full limit to dark red near zero. The digits can use the same color. Both switches are in the Menu bar tab; the meter is on by default."
            ),
            ReleaseNoteItem(
                id: "thicker-menu-bar-meter",
                introducedIn: "1.3.0",
                icon: "menubar.rectangle",
                title: "Easier to read at a glance",
                detail: "The menu bar meter is thicker and the percentage digits are slightly larger."
            ),
            ReleaseNoteItem(
                id: "colored-popover-meters",
                introducedIn: "1.3.0",
                icon: "gauge.with.dots.needle.33percent",
                title: "Popover meters by remaining limit",
                detail: "Both meters in the popover use the same color scale as the menu bar, so a nearly spent limit is red there too."
            ),
            ReleaseNoteItem(
                id: "hotkey-toggles-details",
                introducedIn: "1.3.0",
                icon: "keyboard",
                title: "Shortcut opens and closes",
                detail: "A second press of the keyboard shortcut closes the detailed limits window."
            ),
            ReleaseNoteItem(
                id: "russian-everywhere",
                introducedIn: "1.3.0",
                icon: "character.bubble",
                title: "Russian in every window",
                detail: "With Russian selected, the detailed limits window, the popover, and low-limit notifications no longer mix in English words."
            ),
            ReleaseNoteItem(
                id: "widget-glass-restored",
                introducedIn: "1.3.0",
                icon: "square.grid.2x2",
                title: "Widget glass is back",
                detail: "Desktop widgets turn into system glass again when a window covers the desktop, in both the beige and the dark design. After an update macOS may need up to a minute to apply it."
            ),
            ReleaseNoteItem(
                id: "widget-layout-fixes",
                introducedIn: "1.3.0",
                icon: "rectangle.3.group",
                title: "Widgets without clipping",
                detail: "Widget text no longer gets cut off, the out-of-date marker shows in every widget size, and the large widget shows its main values without the unused statistics block."
            ),
            ReleaseNoteItem(
                id: "empty-window-fixed",
                introducedIn: "1.3.0",
                icon: "macwindow",
                title: "No empty window at launch",
                detail: "The app no longer opens an empty window when it starts."
            ),
            ReleaseNoteItem(
                id: "menu-bar-refresh-glyph-removed",
                introducedIn: "1.2.401",
                icon: "menubar.rectangle",
                title: "Menu bar without the refresh glyph",
                detail: "The circular refresh arrow no longer appears next to the menu bar percentage. You can still refresh limits from the menu-bar menu, the popover, and Settings."
            ),
            ReleaseNoteItem(
                id: "menu-bar-right-click-action",
                introducedIn: "1.2.401",
                icon: "menubar.rectangle",
                title: "Right-click action",
                detail: "The menu-bar icon has its own right-click action: the context menu, the popover, Settings, or Codex."
            ),
            ReleaseNoteItem(
                id: "codex-opens-without-quitting",
                introducedIn: "1.2.401",
                icon: "checkmark.shield",
                title: "Codex opens without quitting",
                detail: "Choosing Codex from the menu bar or a widget opens the desktop app instead of ending this one."
            ),
            ReleaseNoteItem(
                id: "readable-update-notes",
                introducedIn: "1.2.401",
                icon: "sparkles",
                title: "Update notes you can actually read",
                detail: "This window now comes to the front over other windows and Spaces, and it counts as read only after you confirm it."
            ),
            ReleaseNoteItem(
                id: "widget-click-legacy-setting",
                introducedIn: "1.2.401",
                icon: "cursorarrow.click",
                title: "Widget click follows your setting",
                detail: "Clicking a widget opens the destination you chose, including for widgets installed by an earlier version."
            ),
            ReleaseNoteItem(
                id: "separate-alert-windows",
                introducedIn: "1.2.401",
                icon: "bell.badge",
                title: "Separate 5-hour and weekly alerts",
                detail: "Low-limit alerts have their own switch and thresholds for the 5-hour and the weekly limit."
            ),
            ReleaseNoteItem(
                id: "limit-color-level",
                introducedIn: "1.2.400",
                icon: "paintpalette",
                title: "Limit color by level",
                detail: "The remaining percentage in the widget and popover turns warning or critical when the balance drops, so a low limit is visible at a glance."
            ),
            ReleaseNoteItem(
                id: "widget-last-update-time",
                introducedIn: "1.2.400",
                icon: "clock",
                title: "Last update time in widgets",
                detail: "The widget shows when limits were last synced successfully, and a toggle hides the line."
            ),
            ReleaseNoteItem(
                id: "copy-status",
                introducedIn: "1.2.400",
                icon: "doc.on.doc",
                title: "Copy status",
                detail: "A button in the popover copies the plan, percentage, and reset time of each limit window as text."
            ),
            ReleaseNoteItem(
                id: "menu-bar-refresh",
                introducedIn: "1.2.400",
                icon: "arrow.clockwise",
                title: "Refresh from the menu bar",
                detail: "The menu-bar menu refreshes limits on demand and shows that data is loading while the request runs."
            ),
            ReleaseNoteItem(
                id: "widget-click-action",
                introducedIn: "1.2.400",
                icon: "cursorarrow.click",
                title: "Widget click action",
                detail: "Settings choose what a click on a widget opens: the app, the detailed limit window, or Codex."
            ),
            ReleaseNoteItem(
                id: "menu-bar-click-actions",
                introducedIn: "1.2.400",
                icon: "menubar.rectangle",
                title: "Menu bar click actions",
                detail: "The left-click action is configurable, and the right-click menu offers refresh, copy, and quit."
            ),
            ReleaseNoteItem(
                id: "global-shortcut",
                introducedIn: "1.2.400",
                icon: "command",
                title: "Global shortcut",
                detail: "A configurable keyboard shortcut brings the detailed limits window to the front from any app."
            ),
            ReleaseNoteItem(
                id: "quiet-hours",
                introducedIn: "1.2.400",
                icon: "moon.zzz",
                title: "Quiet hours",
                detail: "Low-limit alerts stay quiet during the hours you choose, for example at night. Quiet hours do not mute restoration notifications."
            ),
            ReleaseNoteItem(
                id: "limit-reset-notification",
                introducedIn: "1.2.400",
                icon: "arrow.clockwise.circle",
                title: "Reset notification",
                detail: "If the app observed an exhausted limit, it can notify you when the quota is available again."
            ),
            ReleaseNoteItem(
                id: "settings-diagnostics",
                introducedIn: "1.2.400",
                icon: "wrench.and.screwdriver",
                title: "Diagnostics in Settings",
                detail: "Settings show the data source, the last successful sync, and the CLI response when a refresh fails."
            ),
            ReleaseNoteItem(
                id: "reset-local-data",
                introducedIn: "1.2.400",
                icon: "trash",
                title: "Reset local data",
                detail: "A confirmation-protected button deletes the stored limit snapshot, widget data, notification history, and app settings without touching your Codex account or CLI sign-in."
            ),
            ReleaseNoteItem(
                id: "readable-plan-names",
                introducedIn: "1.2.400",
                icon: "tag",
                title: "Readable plan names",
                detail: "Widgets and the popover show names such as Pro 5x, Pro 20x, and Plus instead of raw plan identifiers."
            ),
            ReleaseNoteItem(
                id: "seven-day-token-chart",
                introducedIn: "1.2.400",
                icon: "chart.bar",
                title: "Seven-day token chart",
                detail: "The large Beige widget plots token usage for the last seven days with date labels."
            ),
            ReleaseNoteItem(
                id: "today-label",
                introducedIn: "1.2.400",
                icon: "calendar",
                title: "TODAY label for fresh data",
                detail: "When the newest token data is from the current day, the large Beige widget labels it TODAY instead of LAST DAY."
            ),
            ReleaseNoteItem(
                id: "menu-bar-template-color",
                introducedIn: "1.2.304",
                icon: "menubar.rectangle",
                title: "Menu bar color correction",
                detail: "The compact indicator now automatically matches the system menu bar: black on light backgrounds and white on dark ones."
            ),
            ReleaseNoteItem(
                id: "widget-glass-regression-fix",
                introducedIn: "1.2.303",
                icon: "rectangle.on.rectangle.angled",
                title: "Desktop widget glass fix",
                detail: "When macOS dims a widget behind another window, it keeps the system glass container instead of only becoming darker."
            ),
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
