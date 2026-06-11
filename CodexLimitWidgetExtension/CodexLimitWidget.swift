import WidgetKit
import SwiftUI

struct CodexLimitEntry: TimelineEntry {
    let date: Date
    let snapshot: LimitSnapshot?
}

struct CodexLimitProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexLimitEntry {
        CodexLimitEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexLimitEntry) -> Void) {
        completion(
            CodexLimitEntry(
                date: Date(),
                snapshot: LimitStore.read() ?? .placeholder
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexLimitEntry>) -> Void) {
        let entry = CodexLimitEntry(
            date: Date(),
            snapshot: LimitStore.read()
        )
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CodexLimitWidgetEntryView: View {
    var entry: CodexLimitProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TerminalLimitWidgetView(
            snapshot: entry.snapshot,
            family: family
        )
        .containerBackground(for: .widget) {
            TerminalWidgetBackground()
        }
    }
}

private struct TerminalLimitWidgetView: View {
    let snapshot: LimitSnapshot?
    let family: WidgetFamily

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
        return TerminalMetric(id: "5H", title: "5-hour quota", window: snapshot.fiveHour)
    }

    private func header(metric: TerminalMetric?, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CODEX LIMIT")
                .font(.system(size: compact ? 10 : (family == .systemMedium ? 13 : 14), weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            if let metric {
                Text(compact ? metric.window.resetClockText : "resets at \(metric.window.resetClockText)")
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

                    Text("5H REMAINING")
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
                        statRow("RESET", metric.window.resetClockText, size: 12)
                    }
                }
                .padding(.top, 2)
            }

            TerminalDivider(color: mutedAccent)

            HStack {
                terminalLine("WEEKLY LIMIT", color: dimText, size: 11)
                Spacer()
                terminalLine("\(snapshot.weekly.leftPercent)%", color: accent, size: 11)
            }

            TerminalMeter(percent: snapshot.weekly.leftPercent, color: accent, height: 12)
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

            Text("5H REMAINING")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)

            Spacer(minLength: 4)

            HStack {
                terminalLine("WEEKLY LIMIT", color: dimText, size: 9.5)
                Spacer(minLength: 6)
                terminalLine("\(snapshot.weekly.leftPercent)%", color: accent, size: 9.5)
            }

            Spacer(minLength: 3)

            TerminalMeter(percent: snapshot.weekly.leftPercent, color: accent, blockCount: 12, height: 10)

            Spacer(minLength: 4)

            statRow("RESET", metric.window.resetClockText, size: 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func largeBody(snapshot: LimitSnapshot, metric: TerminalMetric, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(metric.window.leftPercent)%")
                        .font(.system(size: 82, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .shadow(color: accent.opacity(0.24), radius: 5)

                    Text("5H REMAINING")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                }
                .frame(width: max(178, width * 0.43), alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    statRow("USED", "\(metric.window.usedPercent)%")
                    statRow("LIMIT", metric.id)
                    if let secondary = secondaryMetric(excluding: metric.id) {
                        statRow(secondary.id, "\(secondary.window.leftPercent)%")
                    }
                    statRow("PLAN", (snapshot.planType ?? "--").uppercased())
                }
                .padding(.top, 5)
            }

            Spacer(minLength: 8)
            TerminalDivider(color: mutedAccent)
            Spacer(minLength: 8)

            HStack {
                terminalLine("WEEKLY LIMIT", color: dimText, size: 12)
                Spacer()
                terminalLine("\(snapshot.weekly.leftPercent)%", color: accent, size: 12)
            }
            Spacer(minLength: 5)
            TerminalMeter(percent: snapshot.weekly.leftPercent, color: accent, blockCount: 24)

            Spacer(minLength: 8)
            TerminalDivider(color: mutedAccent.opacity(0.65))
            Spacer(minLength: 8)

            if let usage = snapshot.usage {
                VStack(alignment: .leading, spacing: 5) {
                    statRow("TOKENS", formatTokenCount(usage.lifetimeTokens))
                    statRow("PEAK DAY", formatTokenCount(usage.peakDailyTokens))
                    statRow("LAST DAY", formatTokenCount(usage.lastDailyTokens))
                    if let currentStreakDays = usage.currentStreakDays {
                        statRow("STREAK", "\(currentStreakDays)d")
                    }
                    statRow("MAX TURN", formatDuration(usage.longestRunningTurnSec))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func secondaryMetric(excluding id: String) -> TerminalMetric? {
        guard let snapshot else { return nil }

        if id != "5H" {
            return TerminalMetric(id: "5H", title: "5-hour quota", window: snapshot.fiveHour)
        }

        if id != "WEEKLY" {
            return TerminalMetric(id: "WEEKLY", title: "weekly quota", window: snapshot.weekly)
        }

        return nil
    }

    private func statRow(_ label: String, _ value: String, size: CGFloat = 13) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func compactStat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
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
        Text(text)
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
}

private struct TerminalMeter: View {
    let percent: Int
    let color: Color
    var blockCount = 20
    var height: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<blockCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < filledCount ? color : Color(red: 0.17, green: 0.18, blue: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(Color(red: 0.39, green: 0.48, blue: 0.33).opacity(index < filledCount ? 0.4 : 0.24), lineWidth: 0.6)
                    )
                    .shadow(color: index < filledCount ? color.opacity(0.18) : .clear, radius: 2)
            }
        }
        .frame(height: height)
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
        .description("Shows remaining 5-hour and weekly Codex limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
