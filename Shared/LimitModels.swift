import Foundation

let widgetKindIdentifier = "Codex Limit Widget"

enum TokenCountText {
    static func make(_ value: Int64?) -> String {
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

enum LimitResetClockText {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func make(for date: Date?) -> String {
        guard let date else { return "--" }
        return formatter.string(from: date)
    }
}

enum CodexConnectionState: Equatable {
    case checking
    case ready
    case authenticationRequired
    case cliNotInstalled
    case installing
    case authenticating
    case failed
}

struct WidgetPayload: Codable, Equatable {
    var snapshot: LimitSnapshot?
    var preferences: LimitPreferences
}

struct LimitSnapshot: Codable, Equatable {
    // Some Codex plans return only a weekly window. Keep both windows optional
    // so the UI renders only the limits that actually exist for the account.
    var fiveHour: LimitWindowSnapshot?
    var weekly: LimitWindowSnapshot?
    var credits: CreditsSnapshot?
    var planType: String?
    var usage: AccountUsageSnapshot?
    var updatedAt: Date
    var errorMessage: String?

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 300
    }

    /// Usage statistics only while their reading is recent enough to present.
    /// The limits above keep their own age indicator either way.
    var freshUsage: AccountUsageSnapshot? {
        guard let usage, !usage.isStale else { return nil }
        return usage
    }

    var planDisplayName: String {
        switch planType?.lowercased().replacingOccurrences(of: "_", with: "") {
        case "prolite": return "Pro 5x"
        case "pro": return "Pro 20x"
        case "plus": return "Plus"
        case "free": return "Free"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return planType ?? "--"
        }
    }

    /// Plain-text summary of the current limits for the copy-to-clipboard action.
    func statusText(locale: Locale) -> String {
        let isRussian = locale.identifier.lowercased().hasPrefix("ru")
        func text(_ english: String, _ russian: String) -> String { isRussian ? russian : english }

        var lines: [String] = []
        lines.append(text("Codex Limit status", "Статус Codex Limit"))
        lines.append(text("Plan: \(planDisplayName)", "План: \(planDisplayName)"))

        if let fiveHour {
            lines.append(windowStatusLine(name: text("5 hours", "5 часов"), window: fiveHour, locale: locale, isRussian: isRussian))
        }
        if let weekly {
            lines.append(windowStatusLine(name: text("Week", "Неделя"), window: weekly, locale: locale, isRussian: isRussian))
        }
        if let creditsText = credits?.displayText(maxFractionDigits: 2) {
            lines.append(text("Balance: \(creditsText)", "Баланс: \(creditsText)"))
        }

        lines.append(text("Updated: \(updatedText(locale: locale))", "Обновлено: \(updatedText(locale: locale))"))
        if isStale {
            lines.append(text("Data is older than 5 minutes", "Данные старше 5 минут"))
        }
        if let errorMessage, !errorMessage.isEmpty {
            lines.append(text("Error: \(errorMessage)", "Ошибка: \(errorMessage)"))
        }

        return lines.joined(separator: "\n")
    }

    private func windowStatusLine(
        name: String,
        window: LimitWindowSnapshot,
        locale: Locale,
        isRussian: Bool
    ) -> String {
        let remaining = isRussian ? "осталось \(window.leftPercent)%" : "\(window.leftPercent)% left"
        guard window.resetsAt != nil else { return "\(name): \(remaining)" }
        let resetPrefix = isRussian ? "сброс" : "reset"
        return "\(name): \(remaining), \(resetPrefix) \(window.resetDateTimeText(locale: locale))"
    }

    private func updatedText(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = locale.identifier.lowercased().hasPrefix("ru") ? "d MMM, HH:mm" : "MMM d, HH:mm"
        return formatter.string(from: updatedAt)
    }

    static let placeholder = LimitSnapshot(
        fiveHour: nil,
        weekly: LimitWindowSnapshot(label: "Week", usedPercent: 4, windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(3600 * 24 * 6)),
        credits: nil,
        planType: "pro",
        usage: AccountUsageSnapshot(
            lifetimeTokens: 3_968_663_548,
            peakDailyTokens: 366_993_630,
            longestRunningTurnSec: 3_209,
            currentStreakDays: 25,
            longestStreakDays: 25,
            learnedSkillsCount: 26,
            totalSkillUses: 570,
            totalThreads: 516,
            lastDailyTokens: 51_598_090,
            lastDailyDate: "2026-06-10",
            updatedAt: Date()
        ),
        updatedAt: Date(),
        errorMessage: nil
    )
}

struct CreditsSnapshot: Codable, Equatable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?

    var displayText: String? {
        displayText(maxFractionDigits: 4)
    }

    func displayText(maxFractionDigits: Int) -> String? {
        guard hasCredits else { return nil }
        if unlimited {
            return "∞T"
        }

        guard let balance = formattedBalance(maxFractionDigits: maxFractionDigits) else {
            return nil
        }

        return "\(balance)T"
    }

    private func formattedBalance(maxFractionDigits: Int) -> String? {
        guard let balance else { return nil }
        let trimmed = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) != nil else {
            return nil
        }

        guard let separatorIndex = normalized.firstIndex(of: ".") else {
            return normalized
        }

        let integerPart = normalized[..<separatorIndex]
        let fractionalStart = normalized.index(after: separatorIndex)
        let fractionalPart = normalized[fractionalStart...]
        guard !fractionalPart.isEmpty else {
            return String(integerPart)
        }

        let fractionDigits = max(0, min(maxFractionDigits, 4))
        guard fractionDigits > 0 else {
            return String(integerPart)
        }

        let displayedFraction = String(fractionalPart.prefix(fractionDigits))
            .padding(toLength: fractionDigits, withPad: "0", startingAt: 0)
        return "\(integerPart).\(displayedFraction)"
    }
}

struct LimitWindowSnapshot: Codable, Equatable {
    var label: String
    var usedPercent: Int
    var windowDurationMins: Int?
    var resetsAt: Date?

    static let unavailable = LimitWindowSnapshot(
        label: "Limit",
        usedPercent: 100,
        windowDurationMins: nil,
        resetsAt: nil
    )

    var leftPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }

    var resetText: String {
        guard let resetsAt else { return "reset unknown" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(resetsAt) ? "HH:mm" : "MMM d, HH:mm"
        return formatter.string(from: resetsAt)
    }

    var resetDateTimeText: String {
        resetDateTimeText(locale: Locale(identifier: "en_US_POSIX"))
    }

    func resetDateTimeText(locale: Locale) -> String {
        guard let resetsAt else { return "reset unknown" }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let resetYear = calendar.component(.year, from: resetsAt)
        let formatter = DateFormatter()
        formatter.locale = locale
        let isRussian = locale.identifier.lowercased().hasPrefix("ru")
        if isRussian {
            formatter.dateFormat = resetYear == currentYear ? "d MMM, HH:mm" : "d MMM yyyy, HH:mm"
        } else {
            formatter.dateFormat = resetYear == currentYear ? "MMM d, HH:mm" : "MMM d, yyyy, HH:mm"
        }
        return formatter.string(from: resetsAt)
    }

    /// Short reset stamp of the widget stat columns: the weekday and the time,
    /// lower cased for Russian ("Fri 18:00" / "пт 18:00").
    func resetWeekdayText(locale: Locale) -> String {
        guard let resetsAt else { return "--" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE HH:mm"
        let text = formatter.string(from: resetsAt)
        return locale.identifier.lowercased().hasPrefix("ru") ? text.lowercased() : text
    }
}

struct AccountUsageSnapshot: Codable, Equatable {
    /// Usage reads happen only while the CLI answers, so a reading older than
    /// this window is treated as expired.
    static let staleInterval: TimeInterval = 6 * 60 * 60

    var dailyTokens: [DailyTokenUsage]? = nil

    /// True while this reading carries no timestamp or is older than
    /// `staleInterval`.
    var isStale: Bool {
        guard let updatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > Self.staleInterval
    }

    var latestDayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return lastDailyDate == formatter.string(from: Date()) ? "TODAY" : "LAST DAY"
    }

    var sevenDayTokens: [DailyTokenUsage] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let latest = dailyTokens?.map(\.date).max(), let end = formatter.date(from: latest) else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: end) else { return nil }
            let key = formatter.string(from: date)
            return DailyTokenUsage(date: key, tokens: dailyTokens?.last(where: { $0.date == key })?.tokens)
        }
    }

    /// Mean tokens a day across the seven-day window. Days without data are
    /// skipped, days with zero tokens count.
    var sevenDayAverageTokens: Int64? {
        let values = sevenDayTokens.compactMap(\.tokens)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Int64(values.count)
    }

    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSec: Int64?
    var currentStreakDays: Int64?
    var longestStreakDays: Int64?
    var learnedSkillsCount: Int64?
    var totalSkillUses: Int64?
    var totalThreads: Int64?
    var lastDailyTokens: Int64?
    var lastDailyDate: String?
    /// Timestamp of the successful usage read behind this snapshot. Older saved
    /// snapshots carry no value.
    var updatedAt: Date? = nil
}

struct DailyTokenUsage: Codable, Equatable {
    var date: String
    var tokens: Int64?
}

/// Low-limit alerts are configured independently for each limit window.
enum LowLimitAlertWindow: String, Codable, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: String { rawValue }
}

struct LimitPreferences: Codable, Equatable {
    var widgetShowsFiveHour = true
    var widgetShowsWeekly = true
    var widgetShowsResetTimes = true
    var widgetShowsLastUpdated = false
    var widgetShowsStaleWarning = true
    var showsMenuBarItem = true
    var menuBarMode = MenuBarMode.detailed
    var compactMenuBarMetric = MenuBarCompactMetric.fiveHour
    var menuWindowDesign = MenuWindowDesign.terminal
    var appLanguage = AppLanguage.system
    var lowLimitFiveHourAlertsEnabled = false
    var lowLimitFiveHourThresholds: [Int?] = [10, 15]
    var lowLimitWeeklyAlertsEnabled = false
    var lowLimitWeeklyThresholds: [Int?] = [10, 15]
    var restorationNotificationsEnabled = true
    var quietHoursEnabled = false
    var quietHoursStartMinutes = 22 * 60
    var quietHoursEndMinutes = 8 * 60
    var widgetClickAction = WidgetClickAction.app
    var menuBarLeftClickAction = MenuBarClickAction.popover
    var menuBarRightClickAction = MenuBarRightClickAction.menu
    var hotkeyEnabled = false
    var hotkeyShortcut: HotkeyShortcut?

    /// A window can hold at most this many low-limit alert thresholds.
    static let maximumNotificationThresholds = 5

    static let `default` = LimitPreferences()

    enum CodingKeys: String, CodingKey {
        case widgetShowsFiveHour
        case widgetShowsWeekly
        case widgetShowsResetTimes
        case widgetShowsLastUpdated
        case widgetShowsStaleWarning
        case showsMenuBarItem
        case menuBarMode
        case compactMenuBarMetric
        case menuWindowDesign
        case appLanguage
        case lowLimitFiveHourAlertsEnabled
        case lowLimitFiveHourThresholds
        case lowLimitWeeklyAlertsEnabled
        case lowLimitWeeklyThresholds
        // Legacy 1.2.400 keys. They are read as the migration source and are
        // still written so 1.2.400 keeps working after a downgrade.
        case lowLimitNotificationsEnabled
        case lowLimitNotificationThresholds
        case restorationNotificationsEnabled
        case quietHoursEnabled
        case quietHoursStartMinutes
        case quietHoursEndMinutes
        case widgetClickAction
        case menuBarLeftClickAction
        case menuBarRightClickAction
        case hotkeyEnabled
        case hotkeyShortcut
    }

    init() {}

    var normalizedForCurrentUI: LimitPreferences {
        var preferences = self
        preferences.widgetShowsFiveHour = true
        preferences.widgetShowsWeekly = true
        preferences.widgetShowsResetTimes = true
        preferences.widgetShowsStaleWarning = true
        return preferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgetShowsFiveHour = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsFiveHour) ?? true
        widgetShowsWeekly = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsWeekly) ?? true
        widgetShowsResetTimes = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsResetTimes) ?? true
        widgetShowsLastUpdated = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsLastUpdated) ?? false
        widgetShowsStaleWarning = try container.decodeIfPresent(Bool.self, forKey: .widgetShowsStaleWarning) ?? true
        showsMenuBarItem = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarItem) ?? true
        menuBarMode = (try? container.decodeIfPresent(MenuBarMode.self, forKey: .menuBarMode)) ?? .detailed
        compactMenuBarMetric = try container.decodeIfPresent(MenuBarCompactMetric.self, forKey: .compactMenuBarMetric) ?? .fiveHour
        menuWindowDesign = (try? container.decodeIfPresent(MenuWindowDesign.self, forKey: .menuWindowDesign)) ?? .terminal
        appLanguage = (try? container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage)) ?? .system

        // 1.2.400 stored one enabled flag and one threshold list for both
        // windows. Read those as the migration source and let each per-window
        // key override its own window, so upgrading keeps the user's settings.
        let legacyAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowLimitNotificationsEnabled)
        let legacyThresholds = try container.decodeIfPresent([Int?].self, forKey: .lowLimitNotificationThresholds)

        lowLimitFiveHourAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowLimitFiveHourAlertsEnabled)
            ?? legacyAlertsEnabled
            ?? false
        lowLimitFiveHourThresholds = Self.normalizedNotificationThresholds(
            try container.decodeIfPresent([Int?].self, forKey: .lowLimitFiveHourThresholds)
                ?? legacyThresholds
                ?? [10, 15]
        )
        lowLimitWeeklyAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowLimitWeeklyAlertsEnabled)
            ?? legacyAlertsEnabled
            ?? false
        lowLimitWeeklyThresholds = Self.normalizedNotificationThresholds(
            try container.decodeIfPresent([Int?].self, forKey: .lowLimitWeeklyThresholds)
                ?? legacyThresholds
                ?? [10, 15]
        )

        restorationNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .restorationNotificationsEnabled) ?? true
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? false
        quietHoursStartMinutes = Self.normalizedMinutesOfDay(
            try container.decodeIfPresent(Int.self, forKey: .quietHoursStartMinutes) ?? 22 * 60
        )
        quietHoursEndMinutes = Self.normalizedMinutesOfDay(
            try container.decodeIfPresent(Int.self, forKey: .quietHoursEndMinutes) ?? 8 * 60
        )
        widgetClickAction = (try? container.decodeIfPresent(WidgetClickAction.self, forKey: .widgetClickAction)) ?? .app
        menuBarLeftClickAction = (try? container.decodeIfPresent(MenuBarClickAction.self, forKey: .menuBarLeftClickAction)) ?? .popover
        menuBarRightClickAction = (try? container.decodeIfPresent(MenuBarRightClickAction.self, forKey: .menuBarRightClickAction)) ?? .menu
        hotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? false
        hotkeyShortcut = try? container.decodeIfPresent(HotkeyShortcut.self, forKey: .hotkeyShortcut)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(widgetShowsFiveHour, forKey: .widgetShowsFiveHour)
        try container.encode(widgetShowsWeekly, forKey: .widgetShowsWeekly)
        try container.encode(widgetShowsResetTimes, forKey: .widgetShowsResetTimes)
        try container.encode(widgetShowsLastUpdated, forKey: .widgetShowsLastUpdated)
        try container.encode(widgetShowsStaleWarning, forKey: .widgetShowsStaleWarning)
        try container.encode(showsMenuBarItem, forKey: .showsMenuBarItem)
        try container.encode(menuBarMode, forKey: .menuBarMode)
        try container.encode(compactMenuBarMetric, forKey: .compactMenuBarMetric)
        try container.encode(menuWindowDesign, forKey: .menuWindowDesign)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(lowLimitFiveHourAlertsEnabled, forKey: .lowLimitFiveHourAlertsEnabled)
        try container.encode(lowLimitFiveHourThresholds, forKey: .lowLimitFiveHourThresholds)
        try container.encode(lowLimitWeeklyAlertsEnabled, forKey: .lowLimitWeeklyAlertsEnabled)
        try container.encode(lowLimitWeeklyThresholds, forKey: .lowLimitWeeklyThresholds)
        // Downgrade mirror: 1.2.400 has a single switch and a single list. Keep
        // alerts on if either window wants them and hand it the merged list.
        try container.encode(
            lowLimitFiveHourAlertsEnabled || lowLimitWeeklyAlertsEnabled,
            forKey: .lowLimitNotificationsEnabled
        )
        try container.encode(
            Self.mergedNotificationThresholds([lowLimitFiveHourThresholds, lowLimitWeeklyThresholds]),
            forKey: .lowLimitNotificationThresholds
        )
        try container.encode(restorationNotificationsEnabled, forKey: .restorationNotificationsEnabled)
        try container.encode(quietHoursEnabled, forKey: .quietHoursEnabled)
        try container.encode(quietHoursStartMinutes, forKey: .quietHoursStartMinutes)
        try container.encode(quietHoursEndMinutes, forKey: .quietHoursEndMinutes)
        try container.encode(widgetClickAction, forKey: .widgetClickAction)
        try container.encode(menuBarLeftClickAction, forKey: .menuBarLeftClickAction)
        try container.encode(menuBarRightClickAction, forKey: .menuBarRightClickAction)
        try container.encode(hotkeyEnabled, forKey: .hotkeyEnabled)
        try container.encodeIfPresent(hotkeyShortcut, forKey: .hotkeyShortcut)
    }

    /// Per-window accessors. The UI and the notification manager both go
    /// through these so a window's setting is never read from the other one.
    func lowLimitAlertsEnabled(for window: LowLimitAlertWindow) -> Bool {
        switch window {
        case .fiveHour: return lowLimitFiveHourAlertsEnabled
        case .weekly: return lowLimitWeeklyAlertsEnabled
        }
    }

    mutating func setLowLimitAlertsEnabled(_ isEnabled: Bool, for window: LowLimitAlertWindow) {
        switch window {
        case .fiveHour: lowLimitFiveHourAlertsEnabled = isEnabled
        case .weekly: lowLimitWeeklyAlertsEnabled = isEnabled
        }
    }

    func lowLimitThresholds(for window: LowLimitAlertWindow) -> [Int?] {
        switch window {
        case .fiveHour: return lowLimitFiveHourThresholds
        case .weekly: return lowLimitWeeklyThresholds
        }
    }

    mutating func setLowLimitThresholds(_ thresholds: [Int?], for window: LowLimitAlertWindow) {
        let normalized = Self.normalizedNotificationThresholds(thresholds)
        switch window {
        case .fiveHour: lowLimitFiveHourThresholds = normalized
        case .weekly: lowLimitWeeklyThresholds = normalized
        }
    }

    static func normalizedNotificationThresholds(_ thresholds: [Int?]) -> [Int?] {
        Array(thresholds.prefix(maximumNotificationThresholds)).map { threshold in
            threshold.map { min(100, max(1, $0)) }
        }
    }

    /// One ascending, de-duplicated list for the single-list 1.2.400 encoding.
    static func mergedNotificationThresholds(_ lists: [[Int?]]) -> [Int?] {
        let values = Set(lists.flatMap { $0 }.compactMap { $0 })
        return Array(values.sorted().prefix(maximumNotificationThresholds)).map { Optional($0) }
    }

    static func normalizedMinutesOfDay(_ minutes: Int) -> Int {
        min(24 * 60 - 1, max(0, minutes))
    }

    static func minutesOfDay(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Quiet hours may wrap past midnight (22:00 -> 08:00). Equal start and end
    /// mean the range is empty, so nothing is suppressed.
    func isQuietHoursActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }

        let start = Self.normalizedMinutesOfDay(quietHoursStartMinutes)
        let end = Self.normalizedMinutesOfDay(quietHoursEndMinutes)
        guard start != end else { return false }

        let current = Self.minutesOfDay(from: date, calendar: calendar)
        if start < end {
            return current >= start && current < end
        }
        return current >= start || current < end
    }
}

struct HotkeyShortcut: Codable, Equatable {
    /// Virtual key code from a captured keyboard event.
    var keyCode: Int
    /// Raw modifier flags (NSEvent.ModifierFlags.rawValue) captured with the key.
    var modifiers: Int
}

enum WidgetClickAction: String, Codable, CaseIterable, Identifiable {
    case app
    case details
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app:
            return "Open app"
        case .details:
            return "Limit details"
        case .codex:
            return "Codex"
        }
    }
}

enum MenuBarClickAction: String, Codable, CaseIterable, Identifiable {
    case popover
    case settings
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popover:
            return "Popover"
        case .settings:
            return "Settings"
        case .codex:
            return "Codex"
        }
    }
}

/// Right-click action for the menu-bar icon. This is a separate type on
/// purpose: the context menu itself is not a meaningful left-click action, so
/// `MenuBarClickAction.allCases` (which feeds the left-click picker) stays
/// untouched.
enum MenuBarRightClickAction: String, Codable, CaseIterable, Identifiable {
    case menu
    case popover
    case settings
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menu:
            return "Context menu"
        case .popover:
            return "Popover"
        case .settings:
            return "Settings"
        case .codex:
            return "Codex"
        }
    }

    /// The equivalent left-click action, or nil when the right click should
    /// keep opening the built-in context menu.
    var clickAction: MenuBarClickAction? {
        switch self {
        case .menu:
            return nil
        case .popover:
            return .popover
        case .settings:
            return .settings
        case .codex:
            return .codex
        }
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case english
    case russian

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .russian:
            Locale(identifier: "ru")
        }
    }

    var title: String {
        switch self {
        case .system:
            "System"
        case .english:
            "English"
        case .russian:
            "Russian"
        }
    }
}

enum MenuBarMode: String, Codable, CaseIterable, Identifiable {
    case detailed
    case percentOnly

    var id: String { rawValue }

    static var allCases: [MenuBarMode] {
        [.detailed, .percentOnly]
    }

    var title: String {
        switch self {
        case .detailed:
            return "Detailed"
        case .percentOnly:
            return "Percent"
        }
    }
}

enum MenuBarCompactMetric: String, Codable, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour:
            return "5 hours"
        case .weekly:
            return "Weekly"
        }
    }
}

enum MenuWindowDesign: String, Codable, CaseIterable, Identifiable {
    case terminal
    case editorial
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:
            return "Dark"
        case .editorial:
            return "Beige"
        case .system:
            return "System"
        }
    }

    func resolved(isDark: Bool) -> MenuWindowDesign {
        guard self == .system else { return self }
        return isDark ? .terminal : .editorial
    }
}

enum LimitStore {
    static let filename = "codex-limit-snapshot.json"

    static var hasStoredSnapshot: Bool {
        storageURLs(filename: filename).contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    static func read() -> LimitSnapshot? {
        for url in storageURLs(filename: filename) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.codexLimitDecoder.decode(LimitSnapshot.self, from: data)
            } catch {
                continue
            }
        }
        return nil
    }

    static func write(_ snapshot: LimitSnapshot) throws {
        let data = try JSONEncoder.codexLimitEncoder.encode(snapshot)
        let urls = storageURLs(filename: filename)

        var lastError: Error?
        var didWrite = false
        for url in urls {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                didWrite = true
            } catch {
                lastError = error
            }
        }

        if !didWrite, let lastError {
            throw lastError
        }
        if !didWrite {
            throw LimitStoreError.unavailableStorage
        }
    }

    static func storageURLs(filename: String) -> [URL] {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return [
                support
                    .appendingPathComponent("CodexLimitWidget", isDirectory: true)
                    .appendingPathComponent(filename)
            ]
        }
        return []
    }

    /// Removes one app-owned file from every known storage location.
    @discardableResult
    static func removeStoredFile(named filename: String) -> Bool {
        var didRemove = false
        for url in storageURLs(filename: filename) where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                didRemove = true
            } catch {
                continue
            }
        }
        return didRemove
    }

    @discardableResult
    static func removeStoredSnapshot() -> Bool {
        removeStoredFile(named: filename)
    }
}

enum LimitPreferencesStore {
    static let filename = "codex-limit-settings.json"

    static var hasStoredPreferences: Bool {
        LimitStore.storageURLs(filename: filename).contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    static func read() -> LimitPreferences {
        for url in LimitStore.storageURLs(filename: filename) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.codexLimitDecoder.decode(LimitPreferences.self, from: data).normalizedForCurrentUI
            } catch {
                continue
            }
        }
        return .default
    }

    static func write(_ preferences: LimitPreferences) throws {
        let data = try JSONEncoder.codexLimitEncoder.encode(preferences)
        let urls = LimitStore.storageURLs(filename: filename)

        var lastError: Error?
        var didWrite = false
        for url in urls {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                didWrite = true
            } catch {
                lastError = error
            }
        }

        if !didWrite, let lastError {
            throw lastError
        }
        if !didWrite {
            throw LimitStoreError.unavailableStorage
        }
    }

    @discardableResult
    static func removeStoredPreferences() -> Bool {
        LimitStore.removeStoredFile(named: filename)
    }
}

enum LimitStoreError: Error {
    case unavailableStorage
}

enum WidgetPayloadStore {
    private static let filename = "widget-payload.json"

    static func read() -> WidgetPayload? {
        guard let data = try? Data(contentsOf: storageURL()) else { return nil }
        return try? JSONDecoder.codexLimitDecoder.decode(WidgetPayload.self, from: data)
    }

    static func write(_ payload: WidgetPayload) {
        guard let data = try? JSONEncoder.codexLimitEncoder.encode(payload) else { return }
        let url = storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    @discardableResult
    static func removeStoredPayload() -> Bool {
        let url = storageURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private static func storageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("CodexLimitWidget", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

enum WidgetBridgeClient {
    static let url = URL(string: "http://127.0.0.1:38347/v1/widget-payload")!

    static func fetch() async -> WidgetPayload? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder.codexLimitDecoder.decode(WidgetPayload.self, from: data)
        else {
            return nil
        }
        return payload
    }
}

extension JSONDecoder {
    static var codexLimitDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var codexLimitEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

#if DEBUG
/// Upgrade guard: snapshots saved before `AccountUsageSnapshot.updatedAt`
/// existed must keep decoding, and their statistics must come back without a
/// timestamp so the UI treats them as expired.
enum LegacyUsageSnapshotCheck {
    private static let legacySnapshotJSON = """
    {
      "updatedAt" : "2026-01-01T00:00:00Z",
      "planType" : "pro",
      "weekly" : {
        "label" : "Week",
        "usedPercent" : 12,
        "windowDurationMins" : 10080
      },
      "usage" : {
        "currentStreakDays" : 25,
        "dailyTokens" : [
          { "date" : "2025-12-31", "tokens" : 1500000 }
        ],
        "lastDailyDate" : "2025-12-31",
        "lastDailyTokens" : 1500000,
        "lifetimeTokens" : 3968663548,
        "longestRunningTurnSec" : 3209,
        "longestStreakDays" : 25,
        "peakDailyTokens" : 366993630
      }
    }
    """

    /// Legacy usage reading, or nil when the payload no longer decodes.
    private static var decodedUsage: AccountUsageSnapshot? {
        let data = Data(legacySnapshotJSON.utf8)
        return try? JSONDecoder.codexLimitDecoder.decode(LimitSnapshot.self, from: data).usage
    }

    /// True while the legacy payload still decodes into statistics that carry
    /// no timestamp.
    static func passes() -> Bool {
        guard let usage = decodedUsage else { return false }
        return usage.updatedAt == nil && usage.lifetimeTokens == 3_968_663_548
    }
}
#endif
