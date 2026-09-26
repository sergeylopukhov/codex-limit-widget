import WidgetKit
import SwiftUI

struct CodexLimitWidgetEntryView: View {
    var entry: CodexLimitProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        ZStack {
            widgetContent
        }
        // Keep one unconditional container background: macOS removes it and
        // shows its own glass when the desktop is dimmed behind a window.
        // Returning a clear background here disables that glass.
        .containerBackground(for: .widget) {
            widgetBackground
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
                family: family
            )
        case .editorial:
            EditorialLimitWidgetView(
                snapshot: entry.snapshot,
                preferences: entry.preferences,
                variant: EditorialWidgetVariant(family: family)
            )
        case .system:
            // Keep a visible widget even if WidgetKit delivers a stale
            // system-design value before the appearance resolution runs.
            TerminalLimitWidgetView(
                snapshot: entry.snapshot,
                preferences: entry.preferences,
                family: family
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
