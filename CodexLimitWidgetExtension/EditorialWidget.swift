import WidgetKit
import SwiftUI

enum EditorialWidgetVariant {
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

/// Colors of the beige widget card.
struct EditorialColors {
    var ink: AnyShapeStyle
    var mutedInk: AnyShapeStyle
    var rule: AnyShapeStyle
    var fill: AnyShapeStyle
    var empty: AnyShapeStyle
    var warningInk: AnyShapeStyle
    var criticalInk: AnyShapeStyle

    func heroStyle(for percent: Int) -> AnyShapeStyle {
        switch LimitRemainingLevel.resolve(remainingPercent: percent) {
        case .normal: return ink
        case .warning: return warningInk
        case .critical: return criticalInk
        }
    }

    static let beige = EditorialColors(
        ink: AnyShapeStyle(EditorialPalette.ink),
        mutedInk: AnyShapeStyle(EditorialPalette.mutedInk),
        rule: AnyShapeStyle(EditorialPalette.rule),
        fill: AnyShapeStyle(EditorialPalette.fill),
        empty: AnyShapeStyle(EditorialPalette.empty),
        warningInk: AnyShapeStyle(Color(red: 0.60, green: 0.38, blue: 0.06)),
        criticalInk: AnyShapeStyle(Color(red: 0.62, green: 0.16, blue: 0.12))
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

struct EditorialLimitWidgetView: View {
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
    let variant: EditorialWidgetVariant
    private let colors = EditorialColors.beige
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

                (Text(LocalizedStringKey(metricPrefix)) + Text(verbatim: " \(LimitResetClockText.make(for: metric.resetsAt))"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(colors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // The sync line gets its own row: next to the title it was always clipped.
            editorialSyncLine(snapshot, size: 8)

            VStack(alignment: .leading, spacing: -7) {
                editorialHeroPercent(metric.leftPercent, size: 54)

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
                color: colors.heroStyle(for: percent),
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
                        Text(LimitResetClockText.make(for: metric.resetsAt))
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
                    editorialHeroPercent(metric.leftPercent, size: 50)

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
                EditorialMeter(percent: weekly.leftPercent, height: 10, color: colors.heroStyle(for: weekly.leftPercent), empty: colors.empty, rule: colors.rule)
            } else {
                editorialMeterHeader(remainingLabel, "\(metric.leftPercent)%")
                EditorialMeter(percent: metric.leftPercent, height: 10, color: colors.heroStyle(for: metric.leftPercent), empty: colors.empty, rule: colors.rule)

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
        // Expired readings keep their place in the layout and drop to "--".
        let usage = snapshot.freshUsage
        // The five-hour window leads the card only while the preference keeps it.
        let fiveHour = preferences.widgetShowsFiveHour ? snapshot.fiveHour : nil
        let metric = fiveHour ?? snapshot.weekly ?? .unavailable
        let resetLabel = fiveHour == nil ? "WEEK RESET" : "5H RESET"
        // The weekly reset stamp is already in the header while the card shows the
        // weekly limit, so the stat column falls back to the best streak.
        let showsWeeklyResetStamp = fiveHour != nil
        let contentWidth = max(0, size.width - padding.leading - padding.trailing)
        // The stat column carries the widest localized values, so it takes its
        // width from the card and the hero column yields instead.
        let messageWidth = max(104, contentWidth * 0.32)
        let leftWidth = max(112, contentWidth - messageWidth - 25)

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
                        Text(LimitResetClockText.make(for: metric.resetsAt))
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
                    editorialHeroPercent(metric.leftPercent, size: 80)

                    Text("Remaining")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: leftWidth, alignment: .leading)
                .layoutPriority(1)

                EditorialVerticalRule(color: colors.rule)
                    .frame(width: 1, height: 86)

                // Side column: several short facts, centred on the vertical rule.
                VStack(alignment: .leading, spacing: 3) {
                    heroInfoStat("STREAK", value: streakValue(usage?.currentStreakDays))
                    heroInfoStat("MAX TURN", value: durationValue(usage?.longestRunningTurnSec))
                    heroInfoStat(
                        showsWeeklyResetStamp ? "WEEK RESET" : "BEST STREAK",
                        value: showsWeeklyResetStamp
                            ? weeklyResetValue(snapshot, locale: locale)
                            : streakValue(usage?.longestStreakDays)
                    )
                    heroInfoStat("DAILY AVG", value: Text(verbatim: TokenCountText.make(usage?.sevenDayAverageTokens)))
                }
                .frame(width: messageWidth, alignment: .leading)
                .layoutPriority(2)
            }
            .frame(width: contentWidth, alignment: .leading)

            // Flexible gaps keep every remaining row at its natural height and
            // share the leftover height evenly, so nothing gets stretched or clipped.
            Spacer(minLength: 10)

            if fiveHour != nil, let weekly = snapshot.weekly {
                weeklyMeter(weekly.leftPercent, height: 8, labelSize: 9.5)
            }

            Spacer(minLength: 10)

            HStack(spacing: 14) {
                editorialStat("USED SHORT", "\(metric.usedPercent)%", labelSize: 9.5, valueSize: 15, spacing: 3.5)
                if fiveHour != nil, let weekly = snapshot.weekly {
                    EditorialVerticalRule(color: colors.rule)
                    editorialStat("WEEKLY", "\(weekly.leftPercent)%", labelSize: 9.5, valueSize: 15, spacing: 3.5)
                }
                EditorialVerticalRule(color: colors.rule)
                editorialStat("TOKENS", TokenCountText.make(usage?.lifetimeTokens), labelSize: 9.5, valueSize: 15, spacing: 3.5)
                EditorialVerticalRule(color: colors.rule)
                editorialStat("PLAN", snapshot.planDisplayName, labelSize: 9.5, valueSize: 15, spacing: 3.5, truncatesValue: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    editorialStat("PEAK DAY", TokenCountText.make(usage?.peakDailyTokens), labelSize: 9.5, valueSize: 15, spacing: 3)
                    editorialStat(usage?.latestDayLabel ?? "LAST DAY", TokenCountText.make(usage?.lastDailyTokens), labelSize: 9.5, valueSize: 15, spacing: 3)
                }
                .frame(width: 112, alignment: .leading)

                EditorialVerticalRule(color: colors.rule)

                sevenDayChart(usage)
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

    private func editorialHeroPercent(_ percent: Int, size: CGFloat) -> some View {
        Text("\(percent)%")
            .font(.system(size: size, weight: .regular, design: .serif))
            .foregroundStyle(colors.heroStyle(for: percent))
            .widgetAccentable()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }

    private func editorialStat(
        _ label: String,
        _ value: String,
        labelSize: CGFloat? = nil,
        valueSize: CGFloat? = nil,
        spacing: CGFloat? = nil,
        truncatesValue: Bool = false
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
                .truncationMode(.tail)
                .minimumScaleFactor(truncatesValue ? 1 : 0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weeklyMeter(_ percent: Int, height: CGFloat, labelSize: CGFloat) -> some View {
        limitMeter(title: "WEEKLY LIMIT", percent: percent, height: height, labelSize: labelSize)
    }

    /// Last successful sync time, or the stale marker while the data is outdated.
    /// The marker takes the row of the sync time, so the layout does not change.
    @ViewBuilder
    private func editorialSyncLine(_ snapshot: LimitSnapshot, size: CGFloat) -> some View {
        if shouldShowStaleWarning(snapshot, preferences: preferences) {
            Text("STALE")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(colors.warningInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if preferences.widgetShowsLastUpdated {
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
                color: colors.heroStyle(for: percent),
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
                .minimumScaleFactor(0.85)

            value
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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

}

private struct EditorialMeter: View {
    let percent: Int
    let height: CGFloat
    let color: AnyShapeStyle
    let empty: AnyShapeStyle
    let rule: AnyShapeStyle

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
                    .widgetAccentable()
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, percent))) / 100)
            }
        }
        .frame(height: height)
        .clipped()
    }
}

private struct EditorialVerticalRule: View {
    let color: AnyShapeStyle

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.75))
            .frame(width: 1)
    }
}

private struct EditorialHorizontalRule: View {
    let color: AnyShapeStyle

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.78))
            .frame(height: 1)
    }
}

struct EditorialWidgetBackground: View {
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
