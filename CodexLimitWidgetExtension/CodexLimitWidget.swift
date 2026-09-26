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

private struct TerminalLimitWidgetView: View {
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
    let family: WidgetFamily
    /// macOS supplies the background (Clear/Tinted look): use system label colors
    /// and leave the glass visible.
    var systemStyled: Bool = false
    @Environment(\.locale) private var locale

    private var accent: Color { systemStyled ? Color.primary : Color(red: 0.52, green: 0.95, blue: 0.43) }
    private var mutedAccent: Color { systemStyled ? Color.primary.opacity(0.45) : Color(red: 0.32, green: 0.56, blue: 0.28) }
    private var dimText: Color { systemStyled ? Color.primary.opacity(0.76) : Color(red: 0.64, green: 0.86, blue: 0.58) }
    private var meterEmpty: Color { systemStyled ? Color.primary.opacity(0.24) : Color(red: 0.17, green: 0.18, blue: 0.14) }
    private var meterEmptyStroke: Color { systemStyled ? Color.primary.opacity(0.32) : Color(red: 0.39, green: 0.48, blue: 0.33).opacity(0.24) }

    private func heroColor(for percent: Int) -> Color {
        guard systemStyled else { return LimitRemainingLevel.terminalColor(for: percent) }
        switch LimitRemainingLevel.resolve(remainingPercent: percent) {
        case .normal: return .primary
        case .warning: return .primary.opacity(0.72)
        case .critical: return .primary.opacity(0.5)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = family == .systemSmall
            let metric = activeMetric
            let padding = contentPadding
            let contentWidth = max(0, proxy.size.width - padding.leading - padding.trailing)

            VStack(alignment: .leading, spacing: 0) {
                header(metric: metric, compact: compact)

                if let snapshot, let metric {
                    switch family {
                    case .systemSmall:
                        fixedGap(5)
                        if preferences.widgetShowsLastUpdated {
                            Text("SYNCED \(LimitSyncTimeText.make(for: snapshot.updatedAt))")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(dimText)
                                .lineLimit(1)
                                .frame(width: contentWidth, alignment: .leading)
                        }
                        compactBody(snapshot: snapshot, metric: metric, width: contentWidth)
                    case .systemLarge:
                        // A tight, fixed gap keeps the hero number close to the title,
                        // matching the colored widget.
                        Spacer(minLength: 6)
                            .frame(maxHeight: 6)
                        largeBody(snapshot: snapshot, metric: metric, width: contentWidth)
                    default:
                        fixedGap(2)
                        TerminalDivider(color: mutedAccent)
                        fixedGap(2)
                        mediumBody(snapshot: snapshot, metric: metric, width: contentWidth)
                    }
                } else {
                    Spacer(minLength: 4)
                    terminalLine("> no limit data", color: dimText, size: compact ? 12 : 14)
                    terminalLine("> waiting for sync", color: accent, size: compact ? 12 : 14)
                    Spacer(minLength: 4)
                }
            }
            .frame(
                width: contentWidth,
                height: max(0, proxy.size.height - padding.top - padding.bottom),
                alignment: .topLeading
            )
            .padding(padding)
        }
    }

    /// Paddings mirror the colored widget so both designs place their blocks the same way.
    private var contentPadding: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .systemLarge:
            return EdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22)
        default:
            return EdgeInsets(top: 8, leading: 12, bottom: 5, trailing: 12)
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
        // Sizes match the colored header height so the rows below line up.
        let titleSize: CGFloat = compact ? 13 : (family == .systemMedium ? 13 : 24)
        let clockSize: CGFloat = compact ? 10 : (family == .systemMedium ? 12 : 15)
        let syncSize: CGFloat = compact ? 8.5 : (family == .systemMedium ? 10 : 11)

        return HStack(alignment: .firstTextBaseline) {
            Text("CODEX LIMIT")
                .font(.system(size: titleSize, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                if let metric, preferences.widgetShowsResetTimes {
                    Group {
                        if compact {
                            Text(LocalizedStringKey(metric.id)) + Text(verbatim: " \(metric.window.resetClockText)")
                        } else {
                            Text("resets at") + Text(verbatim: " \(metric.window.resetClockText)")
                        }
                    }
                        .font(.system(size: clockSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                if !compact, preferences.widgetShowsLastUpdated, let syncedAt = snapshot?.updatedAt {
                    Text("SYNCED \(LimitSyncTimeText.make(for: syncedAt))")
                        .font(.system(size: syncSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
    }

    private func mediumBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        let metricColor = heroColor(for: metric.window.leftPercent)
        let leftWidth = max(116, width * 0.42)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(metric.window.leftPercent)%")
                        .font(.system(size: 54, weight: .black, design: .monospaced))
                        .foregroundStyle(metricColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: systemStyled ? .clear : metricColor.opacity(0.24), radius: 5)

                    Text(LocalizedStringKey(metric.remainingLabel))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(width: leftWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    statRow("PLAN", snapshot.planDisplayName, size: 12)
                    statRow("LIMIT", metric.id, size: 12)
                    if let secondary = secondaryMetric(excluding: metric.id) {
                        statRow(
                            secondary.id,
                            "\(secondary.window.leftPercent)%",
                            size: 12,
                            valueColor: heroColor(for: secondary.window.leftPercent)
                        )
                    } else {
                        statRow("USED", "\(metric.window.usedPercent)%", size: 12)
                    }
                }
                .padding(.top, 2)
            }
            .frame(width: width, alignment: .leading)

            fixedGap(2)
            TerminalDivider(color: mutedAccent)
            fixedGap(2)

            if shouldShowStaleWarning(snapshot), secondaryMetric(excluding: metric.id) != nil {
                HStack {
                    terminalLine("STALE DATA", color: dimText, size: 11)
                    Spacer()
                }
                .frame(width: width, alignment: .leading)
                fixedGap(2)
            }

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                terminalMeterHeader("WEEKLY LIMIT", "\(weekly.leftPercent)%", width: width)
                fixedGap(3)
                TerminalMeter(
                    percent: weekly.leftPercent,
                    color: heroColor(for: weekly.leftPercent),
                    emptyColor: meterEmpty,
                    emptyStroke: meterEmptyStroke,
                    blockCount: 24,
                    height: 10,
                    glow: !systemStyled
                )
                .frame(width: width)
            } else {
                terminalMeterHeader(metric.remainingLabel, "\(metric.window.leftPercent)%", width: width)
                fixedGap(3)
                TerminalMeter(percent: metric.window.leftPercent, color: metricColor, emptyColor: meterEmpty, emptyStroke: meterEmptyStroke, blockCount: 24, height: 10, glow: !systemStyled)
                    .frame(width: width)

                if preferences.widgetShowsResetTimes {
                    fixedGap(2)
                    terminalMeterHeader(
                        "NEXT RESET",
                        metric.window.resetDateTimeText(locale: locale).uppercased(with: locale),
                        width: width
                    )
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func compactBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        let metricColor = heroColor(for: metric.window.leftPercent)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: -6) {
                Text("\(metric.window.leftPercent)%")
                    .font(.system(size: 52, weight: .black, design: .monospaced))
                    .foregroundStyle(metricColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .shadow(color: systemStyled ? .clear : metricColor.opacity(0.22), radius: 4)

                Text(LocalizedStringKey(metric.remainingLabel))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(dimText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                terminalMeterHeader("WEEK", "\(weekly.leftPercent)%", width: width, size: 9.5)
                fixedGap(3)
                TerminalMeter(
                    percent: weekly.leftPercent,
                    color: heroColor(for: weekly.leftPercent),
                    emptyColor: meterEmpty,
                    emptyStroke: meterEmptyStroke,
                    blockCount: 12,
                    height: 8,
                    glow: !systemStyled
                )
                .frame(width: width)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func largeBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        let messageWidth: CGFloat = 100
        let leftWidth = max(150, width - messageWidth - 25)
        let metricColor = heroColor(for: metric.window.leftPercent)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: -6) {
                    Text("\(metric.window.leftPercent)%")
                        .font(.system(size: 80, weight: .black, design: .monospaced))
                        .foregroundStyle(metricColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .shadow(color: systemStyled ? .clear : metricColor.opacity(0.24), radius: 5)

                    Text(LocalizedStringKey(metric.remainingLabel))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: leftWidth, alignment: .leading)
                .layoutPriority(2)

                TerminalVerticalDivider(color: mutedAccent)
                    .frame(height: 86)

                VStack(alignment: .leading, spacing: 3) {
                    if shouldShowStaleWarning(snapshot) {
                        terminalInfoStat("STATUS", value: Text(LocalizedStringKey("STALE")), valueColor: dimText)
                    }
                    terminalInfoStat("STREAK", value: streakValue(snapshot.usage))
                    terminalInfoStat("MAX TURN", value: durationValue(snapshot.usage?.longestRunningTurnSec))
                    terminalInfoStat("THREADS", value: countValue(snapshot.usage?.totalThreads))
                    terminalInfoStat("SKILLS", value: countValue(snapshot.usage?.learnedSkillsCount))
                }
                .frame(width: messageWidth, alignment: .leading)
                .layoutPriority(1)
            }
            .frame(width: width, alignment: .leading)

            Spacer(minLength: 10)

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                terminalMeterHeader("WEEKLY LIMIT", "\(weekly.leftPercent)%", width: width, size: 10)
                fixedGap(3)
                TerminalMeter(
                    percent: weekly.leftPercent,
                    color: heroColor(for: weekly.leftPercent),
                    emptyColor: meterEmpty,
                    emptyStroke: meterEmptyStroke,
                    blockCount: 24,
                    height: 8,
                    glow: !systemStyled
                )
                .frame(width: width)
            } else {
                terminalMeterHeader(metric.remainingLabel, "\(metric.window.leftPercent)%", width: width, size: 10)
                fixedGap(3)
                TerminalMeter(percent: metric.window.leftPercent, color: metricColor, emptyColor: meterEmpty, emptyStroke: meterEmptyStroke, blockCount: 24, height: 8, glow: !systemStyled)
                    .frame(width: width)
            }

            Spacer(minLength: 10)

            HStack(spacing: 14) {
                terminalStat("USED SHORT", "\(metric.window.usedPercent)%", labelSize: 9.5, valueSize: 15)
                if preferences.widgetShowsWeekly, let weekly = snapshot.weekly {
                    TerminalVerticalDivider(color: mutedAccent)
                    terminalStat("WEEKLY", "\(weekly.leftPercent)%", labelSize: 9.5, valueSize: 15)
                }
                TerminalVerticalDivider(color: mutedAccent)
                terminalStat("TOKENS", formatTokenCount(snapshot.usage?.lifetimeTokens), labelSize: 9.5, valueSize: 15)
                TerminalVerticalDivider(color: mutedAccent)
                terminalStat("PLAN", snapshot.planDisplayName, labelSize: 9.5, valueSize: 15)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    terminalStat(
                        "PEAK DAY",
                        formatTokenCount(snapshot.usage?.peakDailyTokens),
                        labelSize: 9.5,
                        valueSize: 15
                    )
                    terminalStat(
                        snapshot.usage?.latestDayLabel ?? "LAST DAY",
                        formatTokenCount(snapshot.usage?.lastDailyTokens),
                        labelSize: 9.5,
                        valueSize: 15
                    )
                }
                .frame(width: 112, alignment: .leading)

                TerminalVerticalDivider(color: mutedAccent)

                tokenBarChart(snapshot.usage, barsHeight: 36)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// Label on the left, value on the right, mirroring the colored meter header.
    private func terminalMeterHeader(_ label: String, _ value: String, width: CGFloat, size: CGFloat = 11) -> some View {
        HStack {
            terminalLine(label, color: dimText, size: size)
            Spacer(minLength: 8)
            terminalLine(value, color: accent, size: size)
        }
        .frame(width: width, alignment: .leading)
    }

    /// Label above value, used for the stat rows that sit in the colored grid.
    private func terminalStat(
        _ label: String,
        _ value: String,
        labelSize: CGFloat,
        valueSize: CGFloat,
        valueColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label))
                .font(.system(size: labelSize, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor ?? accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Seven-day token bars in the terminal palette, placed where the colored
    /// widget draws its chart.
    private func tokenBarChart(_ usage: AccountUsageSnapshot?, barsHeight: CGFloat) -> some View {
        let days = usage?.sevenDayTokens ?? []
        let maximum = max(1, days.compactMap(\.tokens).max() ?? 1)
        let gap: CGFloat = 5

        return Group {
            if days.isEmpty {
                Color.clear.frame(height: 1)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7D TOKENS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)

                    GeometryReader { geometry in
                        let count = max(1, days.count)
                        let barWidth = max(2, (geometry.size.width - gap * CGFloat(count - 1)) / CGFloat(count))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .bottom, spacing: gap) {
                                ForEach(days.indices, id: \.self) { index in
                                    let day = days[index]
                                    let tokens = max(0, day.tokens ?? 0)
                                    let height = tokens > 0 ? max(3, barsHeight * CGFloat(tokens) / CGFloat(maximum)) : 2

                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(tokens > 0
                                              ? accent.opacity(index == days.count - 1 ? 0.95 : 0.55)
                                              : mutedAccent.opacity(0.9))
                                        .frame(width: barWidth, height: height)
                                        .frame(width: barWidth, height: barsHeight, alignment: .bottom)
                                        .accessibilityLabel(day.tokens == nil
                                                            ? "\(day.date): unavailable"
                                                            : "\(day.date): \(tokens) tokens")
                                }
                            }
                            .frame(height: barsHeight, alignment: .bottom)

                            Rectangle()
                                .fill(mutedAccent.opacity(0.7))
                                .frame(height: 1)

                            HStack(spacing: gap) {
                                ForEach(days.indices, id: \.self) { index in
                                    Text(terminalAxisLabel(for: days, at: index))
                                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(dimText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(width: barWidth,
                                               alignment: index == 0 ? .leading : (index == days.count - 1 ? .trailing : .center))
                                }
                            }
                            .frame(height: 9)
                        }
                        .frame(width: geometry.size.width, alignment: .leading)
                    }
                    .frame(height: barsHeight + 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func terminalAxisLabel(for days: [DailyTokenUsage], at index: Int) -> String {
        guard index == 0 || index == days.count - 1, days.indices.contains(index) else { return "" }
        return String(days[index].date.suffix(5)).replacingOccurrences(of: "-", with: "/")
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

    /// Compact fact for the terminal large widget's side column: label above value.
    private func terminalInfoStat(_ label: String, value: Text, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            value
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor ?? accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ label: String, _ value: String, size: CGFloat = 13, valueColor: Color? = nil) -> some View {
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
                .foregroundStyle(valueColor ?? accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let emptyColor: Color
    let emptyStroke: Color
    var blockCount = 20
    var height: CGFloat = 13
    var glow: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let safeCount = max(1, blockCount)
            let blockWidth = max(1, (proxy.size.width - spacing * CGFloat(safeCount - 1)) / CGFloat(safeCount))

            HStack(spacing: spacing) {
                ForEach(0..<safeCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < filledCount ? color : emptyColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(index < filledCount ? color.opacity(0.4) : emptyStroke, lineWidth: 0.6)
                        )
                        .shadow(color: glow && index < filledCount ? color.opacity(0.18) : .clear, radius: 2)
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

private struct TerminalVerticalDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.72))
            .frame(width: 1)
    }
}

private struct TerminalWidgetBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.025, green: 0.029, blue: 0.026))

            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.25, blue: 0.15).opacity(0.20),
                    .clear,
                    Color.black.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

/// Colors of one widget card. `beige` paints the app's own card; `system` is
/// used when macOS supplies the glass background instead.
private struct EditorialColors {
    var ink: Color
    var mutedInk: Color
    var rule: Color
    var fill: Color
    var empty: Color
    var warningInk: Color
    var criticalInk: Color

    func heroColor(for percent: Int) -> Color {
        switch LimitRemainingLevel.resolve(remainingPercent: percent) {
        case .normal: return ink
        case .warning: return warningInk
        case .critical: return criticalInk
        }
    }

    static let beige = EditorialColors(
        ink: EditorialPalette.ink,
        mutedInk: EditorialPalette.mutedInk,
        rule: EditorialPalette.rule,
        fill: EditorialPalette.fill,
        empty: EditorialPalette.empty,
        warningInk: Color(red: 0.60, green: 0.38, blue: 0.06),
        criticalInk: Color(red: 0.62, green: 0.16, blue: 0.12)
    )

    /// System rendering: standard label colors, the remaining-limit level fades the number.
    static let system = EditorialColors(
        ink: .primary,
        mutedInk: .primary.opacity(0.74),
        rule: .primary.opacity(0.45),
        fill: .primary.opacity(0.92),
        empty: .primary.opacity(0.24),
        warningInk: .primary.opacity(0.78),
        criticalInk: .primary.opacity(0.58)
    )
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
    var colors: EditorialColors = .beige
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

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Limit")
                    .font(.system(size: 13.5, weight: .regular, design: .serif))
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                (Text(LocalizedStringKey(metricPrefix)) + Text(verbatim: " \(metric.resetClockText)"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // The sync line gets its own row: next to the title it was always clipped.
            editorialSyncLine(snapshot, size: 8)

            VStack(alignment: .leading, spacing: -7) {
                Text("\(metric.leftPercent)%")
                    .font(.system(size: 54, weight: .regular, design: .serif))
                    .foregroundStyle(colors.heroColor(for: metric.leftPercent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text("Remaining")
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 3)

            if snapshot.fiveHour != nil, let weekly = snapshot.weekly {
                compactMeter(title: "WEEK", percent: weekly.leftPercent, height: 7, labelSize: 9)
            }
        }
        .padding(padding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Compact meter row for the small widget: a short label, the value and the bar.
    private func compactMeter(title: String, percent: Int, height: CGFloat, labelSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(verbatim: "\(percent)%")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)
            }

            EditorialMeter(
                percent: percent,
                height: height,
                color: colors.heroColor(for: percent),
                empty: colors.empty,
                rule: colors.rule
            )
        }
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
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(LocalizedStringKey(resetLabel))
                            .font(.system(size: 7.5, weight: .semibold))
                        Text(metric.resetClockText)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                    }
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    editorialSyncLine(snapshot, size: 8.5)
                }
            }

            EditorialHorizontalRule(color: colors.rule)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -5) {
                    Text("\(metric.leftPercent)%")
                        .font(.system(size: 50, weight: .regular, design: .serif))
                        .foregroundStyle(colors.heroColor(for: metric.leftPercent))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text("Remaining")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: leftWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    editorialMediumStatRow("PLAN", snapshot.planDisplayName)
                    editorialMediumStatRow("LIMIT", metricID)
                    if let secondaryMetric {
                        editorialMediumStatRow("WEEKLY", "\(secondaryMetric.leftPercent)%")
                    } else {
                        editorialMediumStatRow("USED", "\(metric.usedPercent)%")
                    }
                }
                .padding(.top, 1)
            }

            EditorialHorizontalRule(color: colors.rule)

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metricID != "WEEKLY" {
                editorialMeterHeader("WEEKLY LIMIT", "\(weekly.leftPercent)%")
                EditorialMeter(percent: weekly.leftPercent, height: 10, color: colors.heroColor(for: weekly.leftPercent), empty: colors.empty, rule: colors.rule)
            } else {
                editorialMeterHeader(remainingLabel, "\(metric.leftPercent)%")
                EditorialMeter(percent: metric.leftPercent, height: 10, color: colors.heroColor(for: metric.leftPercent), empty: colors.empty, rule: colors.rule)

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
        let padding = EdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22)
        let metric = snapshot.fiveHour ?? snapshot.weekly ?? .unavailable
        let resetLabel = snapshot.fiveHour == nil ? "WEEK RESET" : "5H RESET"
        let contentWidth = max(0, size.width - padding.leading - padding.trailing)
        let messageWidth: CGFloat = 100
        let leftWidth = max(150, contentWidth - messageWidth - 25)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Codex Limit")
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(LocalizedStringKey(resetLabel))
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(metric.resetClockText)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                    }

                    editorialSyncLine(snapshot, size: 8.5)
                }
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            // A tight, fixed gap keeps the hero number close to the title.
            Spacer(minLength: 6)
                .frame(maxHeight: 6)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: -6) {
                    Text("\(metric.leftPercent)%")
                        .font(.system(size: 80, weight: .regular, design: .serif))
                        .foregroundStyle(colors.heroColor(for: metric.leftPercent))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text("Remaining")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: leftWidth, alignment: .leading)
                .layoutPriority(2)

                EditorialVerticalRule(color: colors.rule)
                    .frame(width: 1, height: 86)

                // Side column: several short facts, centred on the vertical rule.
                VStack(alignment: .leading, spacing: 3) {
                    heroInfoStat("STREAK", value: streakValue(snapshot.usage))
                    heroInfoStat("MAX TURN", value: durationValue(snapshot.usage?.longestRunningTurnSec))
                    heroInfoStat("THREADS", value: countValue(snapshot.usage?.totalThreads))
                    heroInfoStat("SKILLS", value: countValue(snapshot.usage?.learnedSkillsCount))
                }
                .frame(width: messageWidth, alignment: .leading)
                .layoutPriority(1)
            }
            .frame(width: contentWidth, alignment: .leading)

            // Flexible gaps keep every remaining row at its natural height and
            // share the leftover height evenly, so nothing gets stretched or clipped.
            Spacer(minLength: 10)

            if snapshot.fiveHour != nil, let weekly = snapshot.weekly {
                weeklyMeter(weekly.leftPercent, height: 8, labelSize: 9.5)
            }

            Spacer(minLength: 10)

            HStack(spacing: 14) {
                editorialStat("USED SHORT", "\(metric.usedPercent)%", labelSize: 9.5, valueSize: 15, spacing: 3.5)
                if snapshot.fiveHour != nil, let weekly = snapshot.weekly {
                    EditorialVerticalRule(color: colors.rule)
                    editorialStat("WEEKLY", "\(weekly.leftPercent)%", labelSize: 9.5, valueSize: 15, spacing: 3.5)
                }
                EditorialVerticalRule(color: colors.rule)
                editorialStat("TOKENS", formatTokenCount(snapshot.usage?.lifetimeTokens), labelSize: 9.5, valueSize: 15, spacing: 3.5)
                EditorialVerticalRule(color: colors.rule)
                editorialStat("PLAN", snapshot.planDisplayName, labelSize: 9.5, valueSize: 15, spacing: 3.5)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    editorialStat("PEAK DAY", formatTokenCount(snapshot.usage?.peakDailyTokens), labelSize: 9.5, valueSize: 15, spacing: 3)
                    editorialStat(snapshot.usage?.latestDayLabel ?? "LAST DAY", formatTokenCount(snapshot.usage?.lastDailyTokens), labelSize: 9.5, valueSize: 15, spacing: 3)
                }
                .frame(width: 112, alignment: .leading)

                EditorialVerticalRule(color: colors.rule)

                sevenDayChart(snapshot.usage)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(padding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func sevenDayChart(_ usage: AccountUsageSnapshot?) -> some View {
        let days = usage?.sevenDayTokens ?? []
        let maximum = max(1, days.compactMap(\.tokens).max() ?? 1)
        let barsHeight: CGFloat = 36
        let gap: CGFloat = 5

        if days.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("7D TOKENS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)

                GeometryReader { geometry in
                    let count = max(1, days.count)
                    let barWidth = max(2, (geometry.size.width - gap * CGFloat(count - 1)) / CGFloat(count))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .bottom, spacing: gap) {
                            ForEach(days.indices, id: \.self) { index in
                                let day = days[index]
                                let tokens = max(0, day.tokens ?? 0)
                                let height = tokens > 0 ? max(3, barsHeight * CGFloat(tokens) / CGFloat(maximum)) : 2

                                RoundedRectangle(cornerRadius: 1)
                                    .fill(tokens > 0
                                          ? colors.ink.opacity(index == days.count - 1 ? 0.85 : 0.45)
                                          : colors.rule.opacity(0.9))
                                    .frame(width: barWidth, height: height)
                                    .frame(width: barWidth, height: barsHeight, alignment: .bottom)
                                    .accessibilityLabel(day.tokens == nil
                                                        ? "\(day.date): unavailable"
                                                        : "\(day.date): \(tokens) tokens")
                            }
                        }
                        .frame(height: barsHeight, alignment: .bottom)

                        Rectangle()
                            .fill(colors.rule.opacity(0.7))
                            .frame(height: 1)

                        HStack(spacing: gap) {
                            ForEach(days.indices, id: \.self) { index in
                                Text(axisLabel(for: days, at: index))
                                    .font(.system(size: 7.5))
                                    .foregroundStyle(colors.mutedInk)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(width: barWidth,
                                           alignment: index == 0 ? .leading : (index == days.count - 1 ? .trailing : .center))
                            }
                        }
                        .frame(height: 9)
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .frame(height: barsHeight + 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Only the first and the last day carry a date, aligned under their bars.
    private func axisLabel(for days: [DailyTokenUsage], at index: Int) -> String {
        guard index == 0 || index == days.count - 1, days.indices.contains(index) else { return "" }
        return String(days[index].date.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }

    private func emptyState(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Limit")
                .font(.system(size: variant == .large ? 31 : 25, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)

            Rectangle()
                .fill(colors.rule.opacity(0.65))
                .frame(height: 1)

            Spacer(minLength: 8)

            Text("No limit data")
                .font(.system(size: variant == .small ? 24 : 32, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text("Waiting for sync")
                .font(.system(size: variant == .small ? 14 : 18, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(colors.mutedInk)

            Spacer(minLength: 8)
        }
        .padding(variant == .small ? 16 : 22)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func editorialStat(
        _ label: String,
        _ value: String,
        labelSize: CGFloat? = nil,
        valueSize: CGFloat? = nil,
        spacing: CGFloat? = nil
    ) -> some View {
        let resolvedLabelSize: CGFloat = labelSize ?? {
            switch variant {
            case .small: return 9
            case .medium: return 7.5
            case .large: return 12
            }
        }()
        let resolvedValueSize: CGFloat = valueSize ?? {
            switch variant {
            case .small: return 15
            case .medium: return 12
            case .large: return 20
            }
        }()
        let resolvedSpacing: CGFloat = spacing ?? (variant == .medium ? 1 : 5)

        return VStack(alignment: .leading, spacing: resolvedSpacing) {
            Text(LocalizedStringKey(label))
                .font(.system(size: resolvedLabelSize, weight: .semibold))
                .foregroundStyle(colors.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: resolvedValueSize, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weeklyMeter(_ percent: Int, height: CGFloat, labelSize: CGFloat) -> some View {
        limitMeter(title: "WEEKLY LIMIT", percent: percent, height: height, labelSize: labelSize)
    }

    /// Last successful sync time; renders nothing while the preference is off.
    @ViewBuilder
    private func editorialSyncLine(_ snapshot: LimitSnapshot, size: CGFloat) -> some View {
        if preferences.widgetShowsLastUpdated {
            Text("SYNCED \(LimitSyncTimeText.make(for: snapshot.updatedAt))")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(colors.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func limitMeter(title: String, percent: Int, height: CGFloat, labelSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                (Text(verbatim: "\(percent)% ") + Text("REMAINING"))
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            EditorialMeter(
                percent: percent,
                height: height,
                color: colors.heroColor(for: percent),
                empty: colors.empty,
                rule: colors.rule
            )
        }
    }

    private func mediumStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(colors.mutedInk)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    /// Compact fact for the large widget's side column: label above value.
    private func heroInfoStat(_ label: String, value: Text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(colors.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            value
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorialMediumStatRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.mutedInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func editorialMeterHeader(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.mutedInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
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
}

private struct EditorialMeter: View {
    let percent: Int
    let height: CGFloat
    let color: Color
    let empty: Color
    let rule: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(empty.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(rule.opacity(0.75), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, percent))) / 100)
            }
        }
        .frame(height: height)
        .clipped()
    }
}

private struct EditorialVerticalRule: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.75))
            .frame(width: 1)
    }
}

private struct EditorialHorizontalRule: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.78))
            .frame(height: 1)
    }
}

private struct EditorialWidgetBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
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

/// Streak length, localized through the shared "%lldd" format ("25d" / "25 дн.").
private func streakValue(_ usage: AccountUsageSnapshot?) -> Text {
    guard let days = usage?.currentStreakDays else { return Text(verbatim: "--") }
    return Text("\(days)d")
}

/// Longest turn, localized through the shared "%lldh %lldm" format.
private func durationValue(_ seconds: Int64?) -> Text {
    guard let seconds else { return Text(verbatim: "--") }
    return Text("\(seconds / 3_600)h \((seconds % 3_600) / 60)m")
}

private func countValue(_ value: Int64?) -> Text {
    guard let value else { return Text(verbatim: "--") }
    return Text("\(value)")
}
