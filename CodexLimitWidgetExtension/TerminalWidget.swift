import WidgetKit
import SwiftUI

struct TerminalLimitWidgetView: View {
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
    let family: WidgetFamily
    @Environment(\.locale) private var locale

    private let accent = AnyShapeStyle(Color(red: 0.52, green: 0.95, blue: 0.43))
    private let mutedAccent = AnyShapeStyle(Color(red: 0.32, green: 0.56, blue: 0.28))
    private let dimText = AnyShapeStyle(Color(red: 0.64, green: 0.86, blue: 0.58))
    private let meterEmpty = AnyShapeStyle(Color(red: 0.17, green: 0.18, blue: 0.14))
    private let meterEmptyStroke = AnyShapeStyle(Color(red: 0.39, green: 0.48, blue: 0.33).opacity(0.24))

    private func heroStyle(for percent: Int) -> AnyShapeStyle {
        AnyShapeStyle(LimitRemainingLevel.terminalColor(for: percent))
    }

    private func meterGlowColor(for percent: Int) -> Color? {
        LimitRemainingLevel.terminalColor(for: percent)
    }

    private var staleMarkerStyle: AnyShapeStyle {
        AnyShapeStyle(LimitRemainingLevel.terminalColor(for: warningLevelPercent))
    }

    private func heroPercent(_ percent: Int, size: CGFloat, minScale: CGFloat, glowOpacity: Double, glowRadius: CGFloat) -> some View {
        Text("\(percent)%")
            .font(.system(size: size, weight: .black, design: .monospaced))
            .foregroundStyle(heroStyle(for: percent))
            .widgetAccentable()
            .lineLimit(1)
            .minimumScaleFactor(minScale)
            .shadow(color: LimitRemainingLevel.terminalColor(for: percent).opacity(glowOpacity), radius: glowRadius)
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
                        // The stale marker replaces the sync time, so the row does
                        // not change the layout of the small widget.
                        if shouldShowStaleWarning(snapshot, preferences: preferences) {
                            Text("STALE")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(staleMarkerStyle)
                                .lineLimit(1)
                                .frame(width: contentWidth, alignment: .leading)
                        } else if preferences.widgetShowsLastUpdated {
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
                            Text(LocalizedStringKey(metric.id)) + Text(verbatim: " \(LimitResetClockText.make(for: metric.window.resetsAt))")
                        } else {
                            Text("resets at") + Text(verbatim: " \(LimitResetClockText.make(for: metric.window.resetsAt))")
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
        let leftWidth = max(116, width * 0.42)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -2) {
                    heroPercent(metric.window.leftPercent, size: 54, minScale: 0.6, glowOpacity: 0.24, glowRadius: 5)

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
                            valueColor: heroStyle(for: secondary.window.leftPercent)
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

            // The medium widget runs out of height first, so the rows below the
            // divider give way in order instead of clipping the meters.
            ViewThatFits(in: .vertical) {
                mediumSecondaryRows(snapshot: snapshot, metric: metric, width: width, showsResetTime: true, showsStaleMarker: true)
                mediumSecondaryRows(snapshot: snapshot, metric: metric, width: width, showsResetTime: false, showsStaleMarker: true)
                mediumSecondaryRows(snapshot: snapshot, metric: metric, width: width, showsResetTime: false, showsStaleMarker: false)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// Meter rows of the medium widget. The first row of `ViewThatFits` keeps both
    /// optional rows, the second drops the reset time, the third drops the stale
    /// marker as well.
    private func mediumSecondaryRows(
        snapshot: LimitSnapshot,
        metric: TerminalMetric,
        width: CGFloat,
        showsResetTime: Bool,
        showsStaleMarker: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsStaleMarker, shouldShowStaleWarning(snapshot, preferences: preferences) {
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
                    color: heroStyle(for: weekly.leftPercent),
                    emptyColor: meterEmpty,
                    emptyStroke: meterEmptyStroke,
                    blockCount: 24,
                    height: 10,
                    glow: meterGlowColor(for: weekly.leftPercent)
                )
                .frame(width: width)
            } else {
                terminalMeterHeader(metric.remainingLabel, "\(metric.window.leftPercent)%", width: width)
                fixedGap(3)
                TerminalMeter(percent: metric.window.leftPercent, color: heroStyle(for: metric.window.leftPercent), emptyColor: meterEmpty, emptyStroke: meterEmptyStroke, blockCount: 24, height: 10, glow: meterGlowColor(for: metric.window.leftPercent))
                    .frame(width: width)

                if showsResetTime, preferences.widgetShowsResetTimes {
                    fixedGap(2)
                    terminalMeterHeader(
                        "NEXT RESET",
                        metric.window.resetDateTimeText(locale: locale).uppercased(with: locale),
                        width: width
                    )
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func compactBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: -6) {
                heroPercent(metric.window.leftPercent, size: 52, minScale: 0.55, glowOpacity: 0.22, glowRadius: 4)

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
                    color: heroStyle(for: weekly.leftPercent),
                    emptyColor: meterEmpty,
                    emptyStroke: meterEmptyStroke,
                    blockCount: 12,
                    height: 8,
                    glow: meterGlowColor(for: weekly.leftPercent)
                )
                .frame(width: width)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func largeBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        // Expired readings keep their place in the layout and drop to "--".
        let usage = snapshot.freshUsage
        // The stat column carries the widest localized values, so it takes its
        // width from the widget and the hero column yields instead.
        let messageWidth = max(104, width * 0.32)
        let leftWidth = max(112, width - messageWidth - 25)
        let metricColor = heroStyle(for: metric.window.leftPercent)
        // The weekly reset stamp belongs to the stat column unless the hero
        // percentage already is the weekly limit and the header carries it.
        let showsWeeklyResetStamp = metric.id != "WEEKLY"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: -6) {
                    heroPercent(metric.window.leftPercent, size: 80, minScale: 0.55, glowOpacity: 0.24, glowRadius: 5)

                    Text(LocalizedStringKey(metric.remainingLabel))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: leftWidth, alignment: .leading)
                .layoutPriority(1)

                TerminalVerticalDivider(color: mutedAccent)
                    .frame(height: 86)

                VStack(alignment: .leading, spacing: 3) {
                    if shouldShowStaleWarning(snapshot, preferences: preferences) {
                        terminalInfoStat("STATUS", value: Text(LocalizedStringKey("STALE")), valueColor: dimText)
                    }
                    terminalInfoStat("STREAK", value: streakValue(usage?.currentStreakDays))
                    terminalInfoStat("MAX TURN", value: durationValue(usage?.longestRunningTurnSec))
                    terminalInfoStat(
                        showsWeeklyResetStamp ? "WEEK RESET" : "BEST STREAK",
                        value: showsWeeklyResetStamp
                            ? weeklyResetValue(snapshot, locale: locale)
                            : streakValue(usage?.longestStreakDays)
                    )
                    terminalInfoStat("DAILY AVG", value: Text(verbatim: TokenCountText.make(usage?.sevenDayAverageTokens)))
                }
                .frame(width: messageWidth, alignment: .leading)
                .layoutPriority(2)
            }
            .frame(width: width, alignment: .leading)

            Spacer(minLength: 10)

            if preferences.widgetShowsWeekly, let weekly = snapshot.weekly, metric.id != "WEEKLY" {
                terminalMeterHeader("WEEKLY LIMIT", "\(weekly.leftPercent)%", width: width, size: 10)
                fixedGap(3)
                TerminalMeter(
                    percent: weekly.leftPercent,
                    color: heroStyle(for: weekly.leftPercent),
                    emptyColor: meterEmpty,
                    emptyStroke: meterEmptyStroke,
                    blockCount: 24,
                    height: 8,
                    glow: meterGlowColor(for: weekly.leftPercent)
                )
                .frame(width: width)
            } else {
                terminalMeterHeader(metric.remainingLabel, "\(metric.window.leftPercent)%", width: width, size: 10)
                fixedGap(3)
                TerminalMeter(percent: metric.window.leftPercent, color: metricColor, emptyColor: meterEmpty, emptyStroke: meterEmptyStroke, blockCount: 24, height: 8, glow: meterGlowColor(for: metric.window.leftPercent))
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
                terminalStat("TOKENS", TokenCountText.make(usage?.lifetimeTokens), labelSize: 9.5, valueSize: 15)
                TerminalVerticalDivider(color: mutedAccent)
                terminalStat("PLAN", snapshot.planDisplayName, labelSize: 9.5, valueSize: 15, truncatesValue: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    terminalStat(
                        "PEAK DAY",
                        TokenCountText.make(usage?.peakDailyTokens),
                        labelSize: 9.5,
                        valueSize: 15
                    )
                    terminalStat(
                        usage?.latestDayLabel ?? "LAST DAY",
                        TokenCountText.make(usage?.lastDailyTokens),
                        labelSize: 9.5,
                        valueSize: 15
                    )
                }
                .frame(width: 112, alignment: .leading)

                TerminalVerticalDivider(color: mutedAccent)

                tokenBarChart(usage, barsHeight: 36)
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
    /// `truncatesValue` keeps long values on one line with an ellipsis instead of
    /// shrinking them below the readable size.
    private func terminalStat(
        _ label: String,
        _ value: String,
        labelSize: CGFloat,
        valueSize: CGFloat,
        valueColor: AnyShapeStyle? = nil,
        truncatesValue: Bool = false
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
                .truncationMode(.tail)
                .minimumScaleFactor(truncatesValue ? 1 : 0.6)
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

    /// Compact fact for the terminal large widget's side column: label above value.
    /// The column is sized from the widget width, so both lines stay close to
    /// their full size instead of shrinking.
    private func terminalInfoStat(_ label: String, value: Text, valueColor: AnyShapeStyle? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            value
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor ?? accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ label: String, _ value: String, size: CGFloat = 13, valueColor: AnyShapeStyle? = nil) -> some View {
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

    private func terminalLine(_ text: String, color: AnyShapeStyle, size: CGFloat) -> Text {
        Text(LocalizedStringKey(text))
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
    }

}

/// Single rule for the stale marker: the preference is on and the snapshot is
/// older than its freshness window. Every widget size and design follows it.
func shouldShowStaleWarning(_ snapshot: LimitSnapshot, preferences: LimitPreferences) -> Bool {
    preferences.widgetShowsStaleWarning && snapshot.isStale
}

/// Remaining percentage that `LimitRemainingLevel` resolves as warning. The
/// markers have no percentage of their own, so they ask for this one to pick the
/// warning tint of the terminal palette.
let warningLevelPercent = 20

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
    let color: AnyShapeStyle
    let emptyColor: AnyShapeStyle
    let emptyStroke: AnyShapeStyle
    var blockCount = 20
    var height: CGFloat = 13
    /// Shadow color of the filled blocks. Only the colored design glows, so the
    /// system design passes nothing and the glass stays flat.
    var glow: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let safeCount = max(1, blockCount)
            let blockWidth = max(1, (proxy.size.width - spacing * CGFloat(safeCount - 1)) / CGFloat(safeCount))

            HStack(spacing: spacing) {
                ForEach(0..<safeCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < filledCount ? color : emptyColor)
                        .widgetAccentable(index < filledCount)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(index < filledCount ? AnyShapeStyle(color.opacity(0.4)) : emptyStroke, lineWidth: 0.6)
                        )
                        .shadow(color: index < filledCount ? glow?.opacity(0.18) ?? .clear : .clear, radius: 2)
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
    let color: AnyShapeStyle

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.72))
            .frame(height: 1)
    }
}

private struct TerminalVerticalDivider: View {
    let color: AnyShapeStyle

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.72))
            .frame(width: 1)
    }
}

struct TerminalWidgetBackground: View {
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

/// Streak length in days, localized through the shared "%lldd" format
/// ("25d" / "25 дн.").
func streakValue(_ days: Int64?) -> Text {
    guard let days else { return Text(verbatim: "--") }
    return Text("\(days)d")
}

/// Weekly reset stamp of the large widget's stat column, or `--` while the weekly
/// window or its reset time is unknown.
func weeklyResetValue(_ snapshot: LimitSnapshot, locale: Locale) -> Text {
    guard let weekly = snapshot.weekly else { return Text(verbatim: "--") }
    return Text(verbatim: weekly.resetWeekdayText(locale: locale))
}

/// Longest turn, localized through the shared "%lldh %lldm" format.
func durationValue(_ seconds: Int64?) -> Text {
    guard let seconds else { return Text(verbatim: "--") }
    return Text("\(seconds / 3_600)h \((seconds % 3_600) / 60)m")
}
