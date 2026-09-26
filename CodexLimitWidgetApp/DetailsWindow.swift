import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
@preconcurrency import UserNotifications

// MARK: - Detailed limits window

@MainActor
final class LimitsWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    private let initialContentSize = NSSize(width: 460, height: 600)
    private var windowController: NSWindowController?

    func show(viewModel: LimitViewModel) {
        let contentView = LimitsDetailWindowView(
            viewModel: viewModel,
            close: { [weak self] in self?.close() }
        )
        .environment(\.locale, viewModel.preferences.appLanguage.locale)

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
        window.title = NSLocalizedString("Codex Limit Details", comment: "Window title of the detailed limits window")
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: contentView)
        window.minSize = NSSize(width: 420, height: 420)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        centerWindowOnMainScreen(window)
        bringToFront(window)
    }

    /// The global shortcut opens the window and closes it again when it is
    /// already on screen.
    func toggle(viewModel: LimitViewModel) {
        if windowController?.window?.isVisible == true {
            close()
        } else {
            show(viewModel: viewModel)
        }
    }

    func close() {
        windowController?.close()
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct LimitsDetailWindowView: View {
    @ObservedObject var viewModel: LimitViewModel
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsCopiedFeedback = false

    var body: some View {
        let design = viewModel.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark)
        let palette = SettingsWindowPalette(design: design)

        VStack(spacing: 0) {
            titleBar(palette: palette)

            Rectangle()
                .fill(palette.rule)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    actions(palette: palette)

                    if let snapshot = viewModel.snapshot {
                        limitsSection(snapshot: snapshot, palette: palette)
                        factsSection(snapshot: snapshot, palette: palette)

                        if let usage = snapshot.usage {
                            usageSection(usage: usage, palette: palette)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            SettingsSectionTitle("Limits", palette: palette)
                            Text("No limit data yet. Refresh to load Codex limits.")
                                .font(palette.noteFont)
                                .foregroundStyle(palette.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 420, minHeight: 420, alignment: .topLeading)
        .background(SettingsWindowBackground(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .onExitCommand {
            close()
        }
    }

    private func titleBar(palette: SettingsWindowPalette) -> some View {
        HStack(spacing: 14) {
            SettingsWindowButton(command: .close, showsSymbol: false)

            Text("Codex Limits")
                .font(palette.titleFont)
                .foregroundStyle(palette.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 12)

            Text(viewModel.snapshot?.planDisplayName ?? "--")
                .font(palette.noteFont)
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    private func actions(palette: SettingsWindowPalette) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsActionButton(
                title: viewModel.isRefreshing ? "Refreshing" : "Refresh",
                systemImage: "arrow.clockwise",
                isDisabled: viewModel.isRefreshing,
                palette: palette
            ) {
                Task { await viewModel.refresh(userInitiated: true) }
            }

            SettingsActionButton(
                title: showsCopiedFeedback ? "Copied" : "Copy status",
                systemImage: showsCopiedFeedback ? "checkmark" : "doc.on.doc",
                isDisabled: viewModel.snapshot == nil,
                palette: palette
            ) {
                copyStatus()
            }

            if viewModel.isRefreshing || viewModel.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.accent)
            }

            Spacer(minLength: 0)
        }
    }

    private func limitsSection(snapshot: LimitSnapshot, palette: SettingsWindowPalette) -> some View {
        let locality = viewModel.preferences.appLanguage.locale

        return VStack(alignment: .leading, spacing: 14) {
            SettingsSectionTitle("Limits", palette: palette)

            if let fiveHour = snapshot.fiveHour {
                limitsRow(
                    title: "5 hours",
                    window: fiveHour,
                    locale: locality,
                    palette: palette
                )
            }

            if let weekly = snapshot.weekly {
                limitsRow(
                    title: "Week",
                    window: weekly,
                    locale: locality,
                    palette: palette
                )
            }

            if snapshot.fiveHour == nil, snapshot.weekly == nil {
                Text("This account returned no limit windows.")
                    .font(palette.noteFont)
                    .foregroundStyle(palette.mutedText)
            }
        }
    }

    private func limitsRow(
        title: String,
        window: LimitWindowSnapshot,
        locale: Locale,
        palette: SettingsWindowPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(LocalizedStringKey(title))
                    .font(palette.labelFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text("\(window.leftPercent)%")
                    .font(palette.labelFont)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(palette.controlTrack)

                    Capsule(style: .continuous)
                        .fill(palette.accent)
                        .frame(width: max(6, proxy.size.width * CGFloat(window.leftPercent) / 100))
                }
            }
            .frame(height: 10)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Used \(window.usedPercent)%")
                    .font(palette.noteFont)
                    .foregroundStyle(palette.mutedText)

                Spacer(minLength: 12)

                Text("Reset \(window.resetDateTimeText(locale: locale))")
                    .font(palette.noteFont)
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func factsSection(snapshot: LimitSnapshot, palette: SettingsWindowPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Status", palette: palette)

            SettingsRow("Plan", palette: palette) {
                Text(snapshot.planDisplayName)
                    .font(palette.controlFont)
                    .foregroundStyle(palette.primaryText)
            }

            if let creditsText = snapshot.credits?.displayText(maxFractionDigits: 4) {
                SettingsRow("Credits", palette: palette) {
                    Text(creditsText)
                        .font(palette.controlFont)
                        .foregroundStyle(palette.primaryText)
                }
            }

            SettingsRow("Data source", palette: palette) {
                Text(viewModel.dataSourceDescription)
                    .font(palette.controlFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            SettingsRow("Last update", palette: palette) {
                Text(DetailFormatting.timestamp(snapshot.updatedAt, locale: viewModel.preferences.appLanguage.locale))
                    .font(palette.controlFont)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if snapshot.isStale {
                Text("Data is older than 5 minutes.")
                    .font(palette.noteFont)
                    .foregroundStyle(Color(red: 0.92, green: 0.60, blue: 0.20))
            }

            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(palette.noteFont)
                    .foregroundStyle(Color(red: 0.92, green: 0.33, blue: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = viewModel.lastCLIErrorMessage {
                Text(errorMessage)
                    .font(palette.noteFont)
                    .foregroundStyle(Color(red: 0.92, green: 0.33, blue: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Usage statistic row. An expired reading keeps the row but replaces the
    /// value with "--".
    private func usageStatistic(
        _ title: String,
        _ value: Text,
        isExpired: Bool,
        palette: SettingsWindowPalette
    ) -> some View {
        SettingsRow(title, palette: palette) {
            (isExpired ? Text(verbatim: "--") : value)
                .font(palette.controlFont)
                .foregroundStyle(palette.primaryText)
        }
    }

    private func usageSection(usage: AccountUsageSnapshot, palette: SettingsWindowPalette) -> some View {
        let locale = viewModel.preferences.appLanguage.locale
        // The limits carry their own timestamp; the statistics come from the
        // usage read, so an expired reading is hidden behind "--".
        let isExpired = usage.isStale

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionTitle("Usage", palette: palette)

            if let lifetimeTokens = usage.lifetimeTokens {
                usageStatistic(
                    "Lifetime tokens",
                    Text(verbatim: DetailFormatting.tokens(lifetimeTokens, locale: locale)),
                    isExpired: isExpired,
                    palette: palette
                )
            }

            if let peakDailyTokens = usage.peakDailyTokens {
                usageStatistic(
                    "Peak day",
                    Text(verbatim: DetailFormatting.tokens(peakDailyTokens, locale: locale)),
                    isExpired: isExpired,
                    palette: palette
                )
            }

            if let lastDailyTokens = usage.lastDailyTokens {
                usageStatistic(
                    "Last day",
                    Text(verbatim: DetailFormatting.tokens(lastDailyTokens, locale: locale)),
                    isExpired: isExpired,
                    palette: palette
                )
            }

            if let currentStreakDays = usage.currentStreakDays {
                usageStatistic(
                    "Current streak",
                    Text("\(currentStreakDays)d"),
                    isExpired: isExpired,
                    palette: palette
                )
            }

            if let totalThreads = usage.totalThreads {
                SettingsRow("Threads", palette: palette) {
                    Text(DetailFormatting.tokens(totalThreads, locale: locale))
                        .font(palette.controlFont)
                        .foregroundStyle(palette.primaryText)
                }
            }
        }
    }

    private func copyStatus() {
        guard StatusClipboard.copy(from: viewModel) else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            showsCopiedFeedback = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.16)) {
                showsCopiedFeedback = false
            }
        }
    }
}

private enum DetailFormatting {
    static func timestamp(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func tokens(_ value: Int64, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
