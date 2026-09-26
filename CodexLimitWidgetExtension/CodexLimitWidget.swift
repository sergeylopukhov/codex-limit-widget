import WidgetKit
import SwiftUI

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

#if DEBUG
/// Extreme widget data for the previews: every option is on, the snapshot is
/// stale, the plan name is long and the values reach the widest layouts.
private enum WidgetPreviewData {
    /// Preview snapshot. The weekly-only variant drops the five-hour window, so
    /// the large widgets show the best streak row instead of the reset stamp.
    /// `staleUsage` ages the statistics while the limits stay current.
    static func snapshot(includingFiveHour: Bool = true, staleUsage: Bool = false) -> LimitSnapshot {
        let fiveHour: LimitWindowSnapshot? = includingFiveHour
            ? LimitWindowSnapshot(
                label: "5h",
                usedPercent: 1,
                windowDurationMins: 300,
                resetsAt: Date().addingTimeInterval(2_400)
            )
            : nil

        return LimitSnapshot(
            fiveHour: fiveHour,
            weekly: LimitWindowSnapshot(
                label: "Week",
                usedPercent: 1,
                windowDurationMins: 10_080,
                resetsAt: Date().addingTimeInterval(3 * 86_400)
            ),
            credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: "1234.5678"),
            planType: "Pro (Business)",
            usage: AccountUsageSnapshot(
                dailyTokens: dailyTokens,
                lifetimeTokens: 987_654_321,
                peakDailyTokens: 123_456_789,
                longestRunningTurnSec: 45_600,
                currentStreakDays: 128,
                longestStreakDays: 365,
                learnedSkillsCount: 256,
                totalSkillUses: 1_024,
                totalThreads: 4_096,
                lastDailyTokens: 98_765_432,
                lastDailyDate: nil,
                updatedAt: staleUsage ? Date().addingTimeInterval(-7 * 60 * 60) : Date()
            ),
            updatedAt: Date().addingTimeInterval(-900),
            errorMessage: nil
        )
    }

    static func preferences(design: MenuWindowDesign, language: AppLanguage, showsFiveHour: Bool = true) -> LimitPreferences {
        var preferences = LimitPreferences()
        preferences.widgetShowsFiveHour = showsFiveHour
        preferences.widgetShowsWeekly = true
        preferences.widgetShowsResetTimes = true
        preferences.widgetShowsLastUpdated = true
        preferences.widgetShowsStaleWarning = true
        preferences.menuWindowDesign = design
        preferences.appLanguage = language
        return preferences
    }

    /// Seven consecutive days, so the token chart has its full length. The dates
    /// are fixed values: the chart only needs the day keys.
    private static let dailyTokens: [DailyTokenUsage] = [
        DailyTokenUsage(date: "2026-09-26", tokens: 10_500_000),
        DailyTokenUsage(date: "2026-09-25", tokens: 9_000_000),
        DailyTokenUsage(date: "2026-09-24", tokens: 7_500_000),
        DailyTokenUsage(date: "2026-09-23", tokens: 6_000_000),
        DailyTokenUsage(date: "2026-09-22", tokens: 4_500_000),
        DailyTokenUsage(date: "2026-09-21", tokens: 3_000_000),
        DailyTokenUsage(date: "2026-09-20", tokens: 1_500_000)
    ]
}

private func widgetPreviewEntry(
    design: MenuWindowDesign,
    language: AppLanguage,
    includingFiveHour: Bool = true,
    showsFiveHour: Bool = true,
    staleUsage: Bool = false
) -> CodexLimitEntry {
    CodexLimitEntry(
        date: .now,
        snapshot: WidgetPreviewData.snapshot(includingFiveHour: includingFiveHour, staleUsage: staleUsage),
        preferences: WidgetPreviewData.preferences(design: design, language: language, showsFiveHour: showsFiveHour)
    )
}

#Preview("Terminal small - EN", as: .systemSmall) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .english)
}

#Preview("Terminal small - RU", as: .systemSmall) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .russian)
}

#Preview("Terminal medium - EN", as: .systemMedium) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .english)
}

#Preview("Terminal medium - RU", as: .systemMedium) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .russian)
}

#Preview("Terminal large - EN", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .english)
}

#Preview("Terminal large - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .russian)
}

#Preview("Editorial small - EN", as: .systemSmall) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .english)
}

#Preview("Editorial small - RU", as: .systemSmall) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .russian)
}

#Preview("Editorial medium - EN", as: .systemMedium) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .english)
}

#Preview("Editorial medium - RU", as: .systemMedium) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .russian)
}

#Preview("Editorial large - EN", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .english)
}

#Preview("Editorial large - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .russian)
}

// Weekly-only snapshots: the stat column carries the best streak row instead of
// the weekly reset stamp.
#Preview("Terminal large week only - EN", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .english, includingFiveHour: false)
}

#Preview("Terminal large week only - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .russian, includingFiveHour: false)
}

#Preview("Editorial large week only - EN", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .english, includingFiveHour: false)
}

#Preview("Editorial large week only - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .russian, includingFiveHour: false)
}

// The snapshot keeps the five-hour window while the preference turns it off: the
// large Beige card shows the weekly percentage and the best streak row.
#Preview("Editorial large 5H off - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .russian, showsFiveHour: false)
}

// Expired usage statistics: the limits keep their values while the statistics
// rows fall back to "--" and the seven-day chart disappears.
#Preview("Terminal large stale usage - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .terminal, language: .russian, staleUsage: true)
}

#Preview("Editorial large stale usage - RU", as: .systemLarge) {
    CodexLimitWidget()
} timeline: {
    widgetPreviewEntry(design: .editorial, language: .russian, staleUsage: true)
}
#endif
