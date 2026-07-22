import WidgetKit
import SwiftUI

private final class TimelineCompletionBox<Value>: @unchecked Sendable {
    let completion: (Value) -> Void

    init(_ completion: @escaping (Value) -> Void) {
        self.completion = completion
    }
}

struct CodexLimitEntry: TimelineEntry {
    let date: Date
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
}

struct CodexLimitProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexLimitEntry {
        CodexLimitEntry(date: Date(), snapshot: .placeholder, preferences: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexLimitEntry) -> Void) {
        let completionBox = TimelineCompletionBox(completion)
        Task {
            let payload = await loadPayload() ?? WidgetPayload(snapshot: .placeholder, preferences: .default)
            completionBox.completion(CodexLimitEntry(date: Date(), snapshot: payload.snapshot, preferences: payload.preferences))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexLimitEntry>) -> Void) {
        let completionBox = TimelineCompletionBox(completion)
        Task {
            let payload = await loadPayload() ?? WidgetPayloadStore.read()
            let entry = CodexLimitEntry(date: Date(), snapshot: payload?.snapshot, preferences: payload?.preferences ?? .default)
            // The menu bar is refreshed every minute. Keep the widget timeline on
            // the same cadence so it does not knowingly display a 15-minute-old
            // limit when WidgetKit has not yet processed an explicit reload.
            let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
            completionBox.completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func loadPayload() async -> WidgetPayload? {
        if let payload = await WidgetBridgeClient.fetch() {
            WidgetPayloadStore.write(payload)
            return payload
        }
        return nil
    }
}

struct CodexLimitWidgetEntryView: View {
    var entry: CodexLimitProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        Group {
            switch entry.preferences.menuWindowDesign.resolved(isDark: colorScheme == .dark) {
            case .terminal:
                TerminalLimitWidgetView(
                    snapshot: entry.snapshot,
                    preferences: entry.preferences,
                    family: family
                )
                .containerBackground(for: .widget) {
                    TerminalWidgetBackground()
                }
            case .editorial:
                EditorialLimitWidgetView(
                    snapshot: entry.snapshot,
                    preferences: entry.preferences,
                    variant: EditorialWidgetVariant(family: family)
                )
                .containerBackground(for: .widget) {
                    EditorialWidgetBackground()
                }
            case .system:
                EmptyView()
            }
        }
        .environment(\.locale, entry.preferences.appLanguage.locale)
        .widgetURL(URL(string: "codexlimitwidget://open"))
    }
}

private struct TerminalLimitWidgetView: View {
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
    let family: WidgetFamily
    @Environment(\.locale) private var locale

    private var accent: Color { Color(red: 0.52, green: 0.95, blue: 0.43) }
    private var mutedAccent: Color { Color(red: 0.32, green: 0.56, blue: 0.28) }
    private var dimText: Color { Color(red: 0.64, green: 0.86, blue: 0.58) }

    var body: some View {
        GeometryReader { proxy in
            let compact = family == .systemSmall
            let metric = activeMetric
            let padding = contentPadding

            VStack(alignment: .leading, spacing: verticalSpacing) {
                header(metric: metric, compact: compact)
                TerminalDivider(color: mutedAccent)

                if let snapshot, let metric {
                    switch family {
                    case .systemSmall:
                        compactBody(snapshot: snapshot, metric: metric)
                    case .systemLarge:
                        largeBody(snapshot: snapshot, metric: metric, width: proxy.size.width)
                    default:
                        mediumBody(snapshot: snapshot, metric: metric, width: proxy.size.width)
                    }
                } else {
                    Spacer(minLength: 4)
                    terminalLine("> no limit data", color: dimText, size: compact ? 12 : 14)
                    terminalLine("> waiting for sync", color: accent, size: compact ? 12 : 14)
                    Spacer(minLength: 4)
                }
            }
            .frame(
                width: max(0, proxy.size.width - padding.leading - padding.trailing),
                height: max(0, proxy.size.height - padding.top - padding.bottom),
                alignment: .topLeading
            )
            .padding(padding)
        }
    }

    private var verticalSpacing: CGFloat {
        switch family {
        case .systemSmall: return 5
        case .systemLarge: return 9
        default: return 5
        }
    }

    private var contentPadding: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .systemLarge:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        default:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        }
    }

    private var activeMetric: TerminalMetric? {
        guard let snapshot else { return nil }
        if preferences.widgetShowsFiveHour, let fiveHour = snapshot.fiveHour {
            return TerminalMetric(id: "5H", title: "5-hour quota", window: fiveHour)
        }
        if preferences.widgetShowsWeekly, let weekly = snapshot.weekly {
            return TerminalMetric(id: "WEEKLY", title: "weekly quota", window: weekly)
        }
        return nil
    }

    private func header(metric: TerminalMetric?, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CODEX LIMIT")
                .font(.system(size: compact ? 10 : (family == .systemMedium ? 13 : 14), weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            if let metric, preferences.widgetShowsResetTimes {
                Group {
                    if compact {
                        Text(metric.window.resetClockText)
                    } else {
                        Text("resets at") + Text(verbatim: " \(metric.window.resetClockText)")
                    }
                }
                    .font(.system(size: compact ? 9 : (family == .systemMedium ? 12 : 13), weight: .semibold, design: .monospaced))
                    .foregroundStyle(dimText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }

    private func mediumBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(metric.window.leftPercent)%")
                        .font(.system(size: 54, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: accent.opacity(0.24), radius: 5)

                    Text(LocalizedStringKey(metric.remainingLabel))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                }
                .frame(width: max(116, width * 0.42), alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    statRow("PLAN", (snapshot.planType ?? "--").uppercased(), size: 12)
                    statRow("LIMIT", metric.id, size: 12)
                    if let secondary = secondaryMetric(excluding: metric.id) {
                        statRow(secondary.id, "\(secondary.window.leftPercent)%", size: 12)
                    } else {
                        statRow("USED", "\(metric.window.usedPercent)%", size: 12)
                    }
                }
                .padding(.top, 2)
            }

            TerminalDivider(color: mutedAccent)

            if shouldShowStaleWarning(snapshot), secondaryMetric(excluding: metric.id) != nil {
                HStack {
                    terminalLine("STALE DATA", color: dimText, size: 11)
                    Spacer()
                }
            }

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                HStack {
                    terminalLine("WEEKLY LIMIT", color: dimText, size: 11)
                    Spacer()
                    terminalLine("\(weekly.leftPercent)%", color: accent, size: 11)
                }

                TerminalMeter(percent: weekly.leftPercent, color: accent, blockCount: 24, height: 12)
            } else {
                HStack {
                    terminalLine(metric.remainingLabel, color: dimText, size: 11)
                    Spacer()
                    terminalLine("\(metric.window.leftPercent)%", color: accent, size: 11)
                }

                TerminalMeter(percent: metric.window.leftPercent, color: accent, blockCount: 24, height: 12)

                if shouldShowStaleWarning(snapshot) {
                    HStack {
                        terminalLine("STATUS", color: dimText, size: 11)
                        Spacer()
                        terminalLine("STALE DATA", color: accent, size: 11)
                    }
                } else if preferences.widgetShowsResetTimes {
                    HStack {
                        terminalLine("NEXT RESET", color: dimText, size: 11)
                        Spacer()
                        terminalLine(
                            metric.window.resetDateTimeText(locale: locale).uppercased(with: locale),
                            color: accent,
                            size: 11
                        )
                    }
                }
            }
        }
    }

    private func compactBody(snapshot: LimitSnapshot, metric: TerminalMetric) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(metric.window.leftPercent)%")
                    .font(.system(size: 38, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .shadow(color: accent.opacity(0.22), radius: 4)

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    compactStat("PLAN", (snapshot.planType ?? "--").uppercased())
                    compactStat("LIMIT", metric.id)
                }
                .padding(.top, 8)
            }

            Text(LocalizedStringKey(metric.remainingLabel))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)

            Spacer(minLength: 4)

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                HStack {
                    terminalLine("WEEKLY LIMIT", color: dimText, size: 9.5)
                    Spacer(minLength: 6)
                    terminalLine("\(weekly.leftPercent)%", color: accent, size: 9.5)
                }

                Spacer(minLength: 3)

                TerminalMeter(percent: weekly.leftPercent, color: accent, blockCount: 12, height: 10)
            } else {
                TerminalMeter(percent: metric.window.leftPercent, color: accent, blockCount: 12, height: 10)
            }

            Spacer(minLength: 4)

            if shouldShowStaleWarning(snapshot) {
                statRow("STALE", "DATA", size: 10)
            } else if preferences.widgetShowsResetTimes {
                statRow("RESET", metric.window.resetClockText, size: 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func largeBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        let contentWidth = max(0, width - contentPadding.leading - contentPadding.trailing)
        let columnGap: CGFloat = 12
        let statsColumnWidth = min(126, max(108, contentWidth * 0.34))
        let percentColumnWidth = max(0, contentWidth - statsColumnWidth - columnGap)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: columnGap) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(metric.window.leftPercent)%")
                        .font(.system(size: 86, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .frame(width: percentColumnWidth, alignment: .leading)
                        .shadow(color: accent.opacity(0.24), radius: 5)

                    Text(LocalizedStringKey(metric.remainingLabel))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: percentColumnWidth, alignment: .leading)
                }
                .frame(width: percentColumnWidth, alignment: .leading)
                .clipped()
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 7) {
                    statRow("USED", "\(metric.window.usedPercent)%", size: 15)
                    statRow("LIMIT", metric.id, size: 15)
                    if let secondary = secondaryMetric(excluding: metric.id) {
                        statRow(secondary.id, "\(secondary.window.leftPercent)%", size: 15)
                    }
                    statRow("PLAN", (snapshot.planType ?? "--").uppercased(), size: 15)
                    if shouldShowStaleWarning(snapshot) {
                        statRow("STALE", "DATA", size: 15)
                    }
                }
                .frame(width: statsColumnWidth, alignment: .trailing)
                .layoutPriority(2)
                .padding(.top, 10)
            }
            .frame(width: contentWidth, alignment: .leading)
            .clipped()

            fixedGap(6)
            TerminalDivider(color: mutedAccent)
            fixedGap(8)

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                HStack {
                    terminalLine("WEEKLY LIMIT", color: dimText, size: 12)
                    Spacer(minLength: 8)
                    terminalLine("\(weekly.leftPercent)%", color: accent, size: 12)
                }
                .frame(width: contentWidth, alignment: .leading)
                fixedGap(5)
                TerminalMeter(percent: weekly.leftPercent, color: accent, blockCount: 24)
                    .frame(width: contentWidth)
            } else {
                HStack {
                    terminalLine(metric.remainingLabel, color: dimText, size: 12)
                    Spacer(minLength: 8)
                    terminalLine("\(metric.window.leftPercent)%", color: accent, size: 12)
                }
                .frame(width: contentWidth, alignment: .leading)
                fixedGap(5)
                TerminalMeter(percent: metric.window.leftPercent, color: accent, blockCount: 24)
                    .frame(width: contentWidth)
            }

            fixedGap(8)
            TerminalDivider(color: mutedAccent.opacity(0.65))
            fixedGap(8)

            if let usage = snapshot.usage {
                VStack(alignment: .leading, spacing: 5) {
                    statRow("TOKENS", formatTokenCount(usage.lifetimeTokens), size: 13)
                    statRow("PEAK DAY", formatTokenCount(usage.peakDailyTokens), size: 13)
                    statRow("LAST DAY", formatTokenCount(usage.lastDailyTokens), size: 13)
                    if let currentStreakDays = usage.currentStreakDays {
                        statRow("STREAK", "\(currentStreakDays)d", size: 13)
                    }
                    statRow("MAX TURN", formatDuration(usage.longestRunningTurnSec), size: 13)
                }
                .frame(width: contentWidth, alignment: .leading)
            }
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func fixedGap(_ height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func secondaryMetric(excluding id: String) -> TerminalMetric? {
        guard let snapshot else { return nil }

        if id != "5H" {
            guard preferences.widgetShowsFiveHour, let fiveHour = snapshot.fiveHour else { return nil }
            return TerminalMetric(id: "5H", title: "5-hour quota", window: fiveHour)
        }

        if id != "WEEKLY" {
            guard preferences.widgetShowsWeekly, let weekly = snapshot.weekly else { return nil }
            return TerminalMetric(id: "WEEKLY", title: "weekly quota", window: weekly)
        }

        return nil
    }

    private func shouldShowStaleWarning(_ snapshot: LimitSnapshot) -> Bool {
        preferences.widgetShowsStaleWarning && snapshot.isStale
    }

    private func statRow(_ label: String, _ value: String, size: CGFloat = 13) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactStat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func terminalLine(_ text: String, color: Color, size: CGFloat) -> Text {
        Text(LocalizedStringKey(text))
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
    }

    private func formatTokenCount(_ value: Int64?) -> String {
        guard let value else { return "--" }

        let number = Double(value)
        if number >= 1_000_000_000 {
            return String(format: "%.2fB", number / 1_000_000_000)
        }
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        }
        if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        }
        return "\(value)"
    }

    private func formatPlainCount(_ value: Int64?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }

    private func formatDuration(_ seconds: Int64?) -> String {
        guard let seconds else { return "--" }

        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct TerminalMetric {
    let id: String
    let title: String
    let window: LimitWindowSnapshot

    var remainingLabel: String {
        id == "5H" ? "5H REMAINING" : "WEEKLY REMAINING"
    }

}

private struct TerminalMeter: View {
    let percent: Int
    let color: Color
    var blockCount = 20
    var height: CGFloat = 13

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let safeCount = max(1, blockCount)
            let blockWidth = max(1, (proxy.size.width - spacing * CGFloat(safeCount - 1)) / CGFloat(safeCount))

            HStack(spacing: spacing) {
                ForEach(0..<safeCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < filledCount ? color : Color(red: 0.17, green: 0.18, blue: 0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(Color(red: 0.39, green: 0.48, blue: 0.33).opacity(index < filledCount ? 0.4 : 0.24), lineWidth: 0.6)
                        )
                        .shadow(color: index < filledCount ? color.opacity(0.18) : .clear, radius: 2)
                        .frame(width: blockWidth, height: height)
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .clipped()
    }

    private var filledCount: Int {
        let count = Int((Double(max(0, min(100, percent))) / 100.0 * Double(blockCount)).rounded(.toNearestOrAwayFromZero))
        return max(0, min(blockCount, count))
    }
}

private struct TerminalDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.72))
            .frame(height: 1)
    }
}

private struct TerminalWidgetBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.025, green: 0.029, blue: 0.026))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(red: 0.38, green: 0.47, blue: 0.33).opacity(0.35), lineWidth: 1.2)

            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.25, blue: 0.15).opacity(0.20),
                    .clear,
                    Color.black.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

private enum EditorialWidgetVariant {
    case small
    case medium
    case large

    init(family: WidgetFamily) {
        switch family {
        case .systemSmall:
            self = .small
        case .systemLarge:
            self = .large
        default:
            self = .medium
        }
    }
}

private enum EditorialPalette {
    static let paper = Color(red: 0.93, green: 0.90, blue: 0.82)
    static let paperLight = Color(red: 0.98, green: 0.96, blue: 0.90)
    static let ink = Color(red: 0.14, green: 0.14, blue: 0.12)
    static let mutedInk = Color(red: 0.43, green: 0.39, blue: 0.31)
    static let rule = Color(red: 0.74, green: 0.68, blue: 0.57)
    static let fill = Color(red: 0.54, green: 0.50, blue: 0.39)
    static let empty = Color(red: 0.90, green: 0.86, blue: 0.77)
}

private struct EditorialLimitWidgetView: View {
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
    let variant: EditorialWidgetVariant
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { proxy in
            if let snapshot {
                switch variant {
                case .small:
                    small(snapshot: snapshot, size: proxy.size)
                case .medium:
                    medium(snapshot: snapshot, size: proxy.size)
                case .large:
                    large(snapshot: snapshot, size: proxy.size)
                }
            } else {
                emptyState(size: proxy.size)
            }
        }
    }

    private func small(snapshot: LimitSnapshot, size: CGSize) -> some View {
        let padding: CGFloat = 16
        let metric = snapshot.fiveHour ?? snapshot.weekly ?? .unavailable
        let metricPrefix = snapshot.fiveHour == nil ? "WEEK" : "5H"

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Limit")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(EditorialPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                (Text(LocalizedStringKey(metricPrefix)) + Text(verbatim: " \(metric.resetClockText)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorialPalette.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: -2) {
                Text("\(metric.leftPercent)%")
                    .font(.system(size: 48, weight: .regular, design: .serif))
                    .foregroundStyle(EditorialPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Text("Remaining")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(EditorialPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if snapshot.fiveHour != nil, let weekly = snapshot.weekly {
                weeklyMeter(weekly.leftPercent, height: 8, labelSize: 9)
            }

            HStack(spacing: 10) {
                editorialStat("USED", "\(metric.usedPercent)%")
                EditorialVerticalRule()
                editorialStat("PLAN", (snapshot.planType ?? "--").uppercased())
            }

        }
        .padding(padding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func medium(snapshot: LimitSnapshot, size: CGSize) -> some View {
        let horizontalPadding: CGFloat = 12
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 5
        let metric = snapshot.fiveHour ?? snapshot.weekly ?? .unavailable
        let resetLabel = snapshot.fiveHour == nil ? "WEEK RESET" : "5H RESET"
        let metricID = snapshot.fiveHour == nil ? "WEEKLY" : "5H"
        let secondaryMetric = snapshot.fiveHour == nil ? nil : snapshot.weekly
        let remainingLabel = snapshot.fiveHour == nil ? "WEEKLY REMAINING" : "5H REMAINING"
        let contentWidth = max(0, size.width - horizontalPadding * 2)
        let leftWidth = max(116, contentWidth * 0.42)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Limit")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(EditorialPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(LocalizedStringKey(resetLabel))
                        .font(.system(size: 7.5, weight: .semibold))
                    Text(metric.resetClockText)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                }
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            EditorialHorizontalRule()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -5) {
                    Text("\(metric.leftPercent)%")
                        .font(.system(size: 50, weight: .regular, design: .serif))
                        .foregroundStyle(EditorialPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text("Remaining")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(EditorialPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: leftWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    editorialMediumStatRow("PLAN", (snapshot.planType ?? "--").uppercased())
                    editorialMediumStatRow("LIMIT", metricID)
                    if let secondaryMetric {
                        editorialMediumStatRow("WEEKLY", "\(secondaryMetric.leftPercent)%")
                    } else {
                        editorialMediumStatRow("USED", "\(metric.usedPercent)%")
                    }
                }
                .padding(.top, 1)
            }

            EditorialHorizontalRule()

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metricID != "WEEKLY" {
                editorialMeterHeader("WEEKLY LIMIT", "\(weekly.leftPercent)%")
                EditorialMeter(percent: weekly.leftPercent, height: 10)
            } else {
                editorialMeterHeader(remainingLabel, "\(metric.leftPercent)%")
                EditorialMeter(percent: metric.leftPercent, height: 10)

                if preferences.widgetShowsResetTimes {
                    editorialMeterHeader(
                        "NEXT RESET",
                        metric.resetDateTimeText(locale: locale).uppercased(with: locale)
                    )
                }
            }
        }
        .frame(width: contentWidth, height: max(0, size.height - topPadding - bottomPadding), alignment: .topLeading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }

    private func large(snapshot: LimitSnapshot, size: CGSize) -> some View {
        let padding = EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 24)
        let metric = snapshot.fiveHour ?? snapshot.weekly ?? .unavailable
        let resetLabel = snapshot.fiveHour == nil ? "WEEK RESET" : "5H RESET"
        let contentWidth = max(0, size.width - padding.leading - padding.trailing)
        let leftWidth = min(176, max(146, contentWidth * 0.50))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Codex Limit")
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(EditorialPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(LocalizedStringKey(resetLabel))
                        .font(.system(size: 13, weight: .semibold))
                    Text(metric.resetClockText)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                }
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -8) {
                    Text("\(metric.leftPercent)%")
                        .font(.system(size: 104, weight: .regular, design: .serif))
                        .foregroundStyle(EditorialPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text("Remaining")
                        .font(.system(size: 38, weight: .regular, design: .serif))
                        .foregroundStyle(EditorialPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: leftWidth, alignment: .leading)
                .layoutPriority(1)

                EditorialVerticalRule()
                    .frame(height: 106)

                VStack(alignment: .leading, spacing: 8) {
                    Text(editorialMessage(for: metric.leftPercent))
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .lineLimit(4)
                        .minimumScaleFactor(0.82)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                }
                .foregroundStyle(EditorialPalette.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)
            }
            .frame(width: contentWidth, alignment: .leading)

            if snapshot.fiveHour != nil, let weekly = snapshot.weekly {
                weeklyMeter(weekly.leftPercent, height: 12, labelSize: 12)
            }

            HStack(spacing: 18) {
                editorialStat("USED", "\(metric.usedPercent)%")
                if snapshot.fiveHour != nil, let weekly = snapshot.weekly {
                    EditorialVerticalRule()
                    editorialStat("WEEKLY", "\(weekly.leftPercent)%")
                }
                EditorialVerticalRule()
                editorialStat("TOKENS", formatTokenCount(snapshot.usage?.lifetimeTokens))
                EditorialVerticalRule()
                editorialStat("PLAN", (snapshot.planType ?? "--").uppercased())
            }

            HStack(spacing: 18) {
                editorialStat("PEAK DAY", formatTokenCount(snapshot.usage?.peakDailyTokens))
                EditorialVerticalRule()
                editorialStat("LAST DAY", formatTokenCount(snapshot.usage?.lastDailyTokens))
                EditorialVerticalRule()
                editorialStat("STREAK", streakText(snapshot.usage))
            }
        }
        .padding(padding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func emptyState(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Limit")
                .font(.system(size: variant == .large ? 31 : 25, weight: .regular, design: .serif))
                .foregroundStyle(EditorialPalette.ink)

            Rectangle()
                .fill(EditorialPalette.rule.opacity(0.65))
                .frame(height: 1)

            Spacer(minLength: 8)

            Text("No limit data")
                .font(.system(size: variant == .small ? 24 : 32, weight: .regular, design: .serif))
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text("Waiting for sync")
                .font(.system(size: variant == .small ? 14 : 18, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(EditorialPalette.mutedInk)

            Spacer(minLength: 8)
        }
        .padding(variant == .small ? 16 : 22)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func editorialStat(_ label: String, _ value: String) -> some View {
        let labelSize: CGFloat = {
            switch variant {
            case .small: return 9
            case .medium: return 7.5
            case .large: return 12
            }
        }()
        let valueSize: CGFloat = {
            switch variant {
            case .small: return 15
            case .medium: return 12
            case .large: return 20
            }
        }()
        let spacing: CGFloat = variant == .medium ? 1 : 5

        return VStack(alignment: .leading, spacing: spacing) {
            Text(LocalizedStringKey(label))
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(EditorialPalette.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: valueSize, weight: .regular, design: .serif))
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weeklyMeter(_ percent: Int, height: CGFloat, labelSize: CGFloat) -> some View {
        limitMeter(title: "WEEKLY LIMIT", percent: percent, height: height, labelSize: labelSize)
    }

    private func limitMeter(title: String, percent: Int, height: CGFloat, labelSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(EditorialPalette.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                (Text(verbatim: "\(percent)% ") + Text("REMAINING"))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(EditorialPalette.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            EditorialMeter(percent: percent, height: height)
        }
    }

    private func mediumStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(EditorialPalette.mutedInk)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func editorialMediumStatRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorialPalette.mutedInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func editorialMeterHeader(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(EditorialPalette.mutedInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .serif))
                .foregroundStyle(EditorialPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func editorialMessage(for percent: Int) -> String {
        if percent >= 60 {
            return "Plenty of limit remains."
        }
        if percent >= 30 {
            return "Keep an eye on pace. You still have room to work."
        }
        return "Slow the pace. Your limit is getting close."
    }

    private func streakText(_ usage: AccountUsageSnapshot?) -> String {
        guard let days = usage?.currentStreakDays else { return "--" }
        return "\(days)d"
    }

    private func formatTokenCount(_ value: Int64?) -> String {
        guard let value else { return "--" }

        let number = Double(value)
        if number >= 1_000_000_000 {
            return String(format: "%.2fB", number / 1_000_000_000)
        }
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        }
        if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        }
        return "\(value)"
    }

    private func formatPlainCount(_ value: Int64?) -> String {
        guard let value else { return "--" }
        return value.formatted()
    }
}

private struct EditorialMeter: View {
    let percent: Int
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(EditorialPalette.empty.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(EditorialPalette.rule.opacity(0.75), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(EditorialPalette.fill)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, percent))) / 100)
            }
        }
        .frame(height: height)
        .clipped()
    }
}

private struct EditorialVerticalRule: View {
    var body: some View {
        Rectangle()
            .fill(EditorialPalette.rule.opacity(0.75))
            .frame(width: 1)
    }
}

private struct EditorialHorizontalRule: View {
    var body: some View {
        Rectangle()
            .fill(EditorialPalette.rule.opacity(0.78))
            .frame(height: 1)
    }
}

private struct EditorialWidgetBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(EditorialPalette.paper)

            LinearGradient(
                colors: [
                    EditorialPalette.paperLight.opacity(0.80),
                    EditorialPalette.paper.opacity(0.35),
                    EditorialPalette.fill.opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(EditorialPalette.rule.opacity(0.52), lineWidth: 1)
        }
    }
}

private extension LimitWindowSnapshot {
    var resetClockText: String {
        guard let resetsAt else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: resetsAt)
    }

}

struct CodexLimitWidget: Widget {
    let kind = widgetKindIdentifier

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexLimitProvider()) { entry in
            CodexLimitWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Codex Limit Widget")
        .description("Shows Codex limits using the selected design, including automatic system appearance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
