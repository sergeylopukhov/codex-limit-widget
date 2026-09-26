import WidgetKit
import SwiftUI

struct CodexLimitWidgetEntryView: View {
    var entry: CodexLimitProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground

    /// macOS draws its own background for the Clear/Tinted widget looks (and on
    /// the lock screen). Then the painted card must stay out of the way so the
    /// system glass shows through, and the content uses system label colors.
    private var usesSystemBackground: Bool {
        !showsContainerBackground || renderingMode != .fullColor
    }

    @ViewBuilder
    var body: some View {
        ZStack {
            widgetContent
        }
        .containerBackground(for: .widget) {
            if usesSystemBackground {
                Color.clear
            } else {
                widgetBackground
            }
        }
        .environment(\.locale, entry.preferences.appLanguage.locale)
        .widgetURL(entry.preferences.widgetClickAction.widgetLink)
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch entry.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark) {
        case .terminal:
            TerminalLimitWidgetView(
                snapshot: entry.snapshot,
                preferences: entry.preferences,
                family: family,
                systemStyled: usesSystemBackground
            )
        case .editorial:
            EditorialLimitWidgetView(
                snapshot: entry.snapshot,
                preferences: entry.preferences,
                variant: EditorialWidgetVariant(family: family),
                colors: usesSystemBackground ? .system : .beige
            )
        case .system:
            // Keep a visible widget even if WidgetKit delivers a stale
            // system-design value before the appearance resolution runs.
            TerminalLimitWidgetView(
                snapshot: entry.snapshot,
                preferences: entry.preferences,
                family: family,
                systemStyled: usesSystemBackground
            )
        }
    }

    @ViewBuilder
    private var widgetBackground: some View {
        switch entry.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark) {
        case .editorial:
            EditorialWidgetBackground()
        case .terminal, .system:
            TerminalWidgetBackground()
        }
    }
}

/// Deep link opened by a widget click, matching the host app's URL handling:
/// `open` for the app window, `details` for the detailed limits window, `codex`
/// for the Codex app.
private extension WidgetClickAction {
    var widgetLink: URL? {
        switch self {
        case .app: return URL(string: "codexlimitwidget://open")
        case .details: return URL(string: "codexlimitwidget://details")
        case .codex: return URL(string: "codexlimitwidget://codex")
        }
    }
}
