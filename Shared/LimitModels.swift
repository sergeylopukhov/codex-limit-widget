import Foundation

let appGroupIdentifier = "group.com.sergeylopukhov.codexlimitwidget"
let widgetKindIdentifier = "Codex Limit Widget"

struct LimitSnapshot: Codable, Equatable {
    // Some Codex plans return only a weekly window. Keep both windows optional
    // so the UI renders only the limits that actually exist for the account.
    var fiveHour: LimitWindowSnapshot?
    var weekly: LimitWindowSnapshot?
    var planType: String?
    var usage: AccountUsageSnapshot?
    var updatedAt: Date
    var errorMessage: String?

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 300
    }

    static let placeholder = LimitSnapshot(
        fiveHour: nil,
        weekly: LimitWindowSnapshot(label: "Week", usedPercent: 4, windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(3600 * 24 * 6)),
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
            lastDailyDate: "2026-06-10"
        ),
        updatedAt: Date(),
        errorMessage: nil
    )
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
        guard let resetsAt else { return "reset unknown" }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let resetYear = calendar.component(.year, from: resetsAt)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = resetYear == currentYear ? "MMM d, HH:mm" : "MMM d, yyyy, HH:mm"
        return formatter.string(from: resetsAt)
    }
}

struct AccountUsageSnapshot: Codable, Equatable {
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
    }

    init() {}

    var normalizedForCurrentUI: LimitPreferences {
        var preferences = self
        preferences.widgetShowsFiveHour = true
        preferences.widgetShowsWeekly = true
        preferences.widgetShowsResetTimes = true
        preferences.widgetShowsLastUpdated = false
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:
            return "Dark"
        case .editorial:
            return "Beige"
        }
    }
}

enum LimitStore {
    static let filename = "codex-limit-snapshot.json"
    private static let defaultsKey = "codex-limit-snapshot-data"

    static func read() -> LimitSnapshot? {
        for url in storageURLs(filename: filename) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.codexLimitDecoder.decode(LimitSnapshot.self, from: data)
            } catch {
                continue
            }
        }
        if let data = sharedDefaults()?.data(forKey: defaultsKey) {
            return try? JSONDecoder.codexLimitDecoder.decode(LimitSnapshot.self, from: data)
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

        if let defaults = sharedDefaults() {
            defaults.set(data, forKey: defaultsKey)
            defaults.synchronize()
            didWrite = true
        }

        if !didWrite, let lastError {
            throw lastError
        }
        if !didWrite {
            throw LimitStoreError.unavailableStorage
        }
    }

    static func storageURLs(filename: String) -> [URL] {
        var urls: [URL] = []

        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(groupURL.appendingPathComponent(filename))
        }

        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                support
                    .appendingPathComponent("CodexLimitWidget", isDirectory: true)
                    .appendingPathComponent(filename)
            )
        }

        urls.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.sergeylopukhov.CodexLimitWidget.WidgetExtension/Data/Library/Application Support/CodexLimitWidget", isDirectory: true)
                .appendingPathComponent(filename)
        )

        return uniqueURLs(urls)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(url)
        }

        return result
    }
}

enum LimitPreferencesStore {
    static let filename = "codex-limit-settings.json"
    private static let defaultsKey = "codex-limit-settings-data"

    static func read() -> LimitPreferences {
        for url in LimitStore.storageURLs(filename: filename) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder.codexLimitDecoder.decode(LimitPreferences.self, from: data).normalizedForCurrentUI
            } catch {
                continue
            }
        }
        if let data = sharedDefaults()?.data(forKey: defaultsKey),
           let preferences = try? JSONDecoder.codexLimitDecoder.decode(LimitPreferences.self, from: data) {
            return preferences.normalizedForCurrentUI
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

        if let defaults = sharedDefaults() {
            defaults.set(data, forKey: defaultsKey)
            defaults.synchronize()
            didWrite = true
        }

        if !didWrite, let lastError {
            throw lastError
        }
        if !didWrite {
            throw LimitStoreError.unavailableStorage
        }
    }
}

enum LimitStoreError: Error {
    case unavailableStorage
}

private func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupIdentifier)
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
