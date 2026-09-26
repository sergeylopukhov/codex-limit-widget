import Foundation
import Network
import os
import ServiceManagement
@preconcurrency import UserNotifications
import WidgetKit

enum LoginItemRegistrationPolicy {
    static let canonicalBundleIdentifier = "com.sergeylopukhov.CodexLimitWidget"
    static let canonicalApplicationPath = "/Applications/Codex Limit Widget.app"

    static func shouldRegister(bundleIdentifier: String?, bundleURL: URL, isDebugBuild: Bool) -> Bool {
        guard !isDebugBuild,
              bundleIdentifier == canonicalBundleIdentifier
        else { return false }

        let canonicalURL = URL(fileURLWithPath: canonicalApplicationPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidateURL = bundleURL
            .standardizedFileURL
            .resolvingSymlinksInPath()

        return candidateURL.path == canonicalURL.path
    }
}

@MainActor
final class LimitViewModel: ObservableObject {
    @Published private(set) var snapshot: LimitSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isInstallingCLI = false
    @Published private(set) var connectionState: CodexConnectionState = .checking
    @Published private(set) var connectionMessage: String?
    @Published private(set) var preferences: LimitPreferences
    @Published private(set) var lastSuccessfulSyncAt: Date?
    @Published private(set) var lastCLIErrorMessage: String?
    @Published private(set) var lastCLIErrorAt: Date?

    private let client = CodexRateLimitClient()
    private let widgetBridge = LoopbackWidgetBridge()
    private let lowLimitNotificationManager = LowLimitNotificationManager()
    private let notificationSetupKey = "systemNotificationsConfigured"
    private let loginItemSetupKey = "loginItemRegistrationCompleted"
    private var timer: Timer?
    private var started = false
    /// Timestamp of the last explicit widget timeline reload. Background polls
    /// reuse it to skip a reload while the widget still shows a fresh reading.
    private var lastWidgetReloadAt: Date?
    private static let widgetReloadInterval: TimeInterval = 15 * 60
    /// Bumped by `resetLocalAppData()` so an in-flight refresh cannot write
    /// freshly fetched data back over a just-cleared local state.
    private var dataGeneration = 0

    init() {
        snapshot = LimitStore.read()
        preferences = LimitPreferencesStore.read()
        lastSuccessfulSyncAt = snapshot?.updatedAt
        lastCLIErrorMessage = snapshot?.errorMessage
        #if DEBUG
        assert(LegacyUsageSnapshotCheck.passes(), "A snapshot saved before usage.updatedAt existed no longer decodes")
        #endif
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        widgetBridge.start()
        widgetBridge.publish(WidgetPayload(snapshot: snapshot, preferences: preferences))
        configureLoginItem()
        configureSystemNotificationsIfNeeded()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func refresh(userInitiated: Bool = false) async {
        guard !isRefreshing, !isAuthenticating, !isInstallingCLI else { return }
        isRefreshing = true
        // A background poll keeps the last reading on screen. Only a manual
        // refresh, or the very first poll without data, shows the checking state.
        if userInitiated || snapshot == nil {
            connectionState = .checking
        }
        connectionMessage = nil
        defer { isRefreshing = false }
        let generation = dataGeneration

        do {
            var fresh = try await client.fetch()
            guard generation == dataGeneration else { return }
            if fresh.usage == nil {
                fresh.usage = snapshot?.usage
            }
            normalizeCompactMenuBarMetric(for: fresh)
            let contentChanged = Self.contentChanged(from: snapshot, to: fresh)
            snapshot = fresh
            do {
                try LimitStore.write(fresh)
            } catch {
                LimitLog.store.error("LimitStore.write failed: \(error.localizedDescription)")
            }
            lastSuccessfulSyncAt = fresh.updatedAt
            lastCLIErrorMessage = nil
            lastCLIErrorAt = nil
            publishSnapshot()
            if contentChanged || widgetReloadIsDue() {
                reloadWidgetTimelines()
            }
            await lowLimitNotificationManager.deliverIfNeeded(for: fresh, preferences: preferences)
            connectionState = .ready
        } catch {
            guard generation == dataGeneration else { return }
            handleRefreshFailure(error)
        }
    }

    func authenticate() async {
        guard !isAuthenticating, !isInstallingCLI, !isRefreshing else { return }

        let cli: CodexCLI
        do {
            cli = try CodexCLI.resolve()
        } catch {
            connectionState = .cliNotInstalled
            connectionMessage = nil
            return
        }

        isAuthenticating = true
        connectionState = .authenticating
        connectionMessage = nil

        do {
            let result = try await cli.run(arguments: ["login"])
            guard result.succeeded else {
                throw CodexCLICommandError.loginFailed(result.combinedOutput)
            }

            let authenticationStatus = try await cli.authenticationStatus()
            isAuthenticating = false

            switch authenticationStatus {
            case .loggedIn:
                await refresh()
            case .notLoggedIn:
                connectionState = .authenticationRequired
                connectionMessage = "Codex login did not complete."
            }
        } catch {
            isAuthenticating = false
            connectionState = .authenticationRequired
            connectionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func installCLI() async {
        guard !isInstallingCLI, !isAuthenticating, !isRefreshing else { return }

        isInstallingCLI = true
        connectionState = .installing
        connectionMessage = nil

        do {
            try await CodexCLIInstaller.install()
            let cli = try CodexCLI.resolve()
            _ = try await cli.version()
            let authenticationStatus = try await cli.authenticationStatus()
            isInstallingCLI = false

            switch authenticationStatus {
            case .loggedIn:
                await refresh()
            case .notLoggedIn:
                await authenticate()
            }
        } catch {
            isInstallingCLI = false
            connectionState = .cliNotInstalled
            connectionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    var isCodexActionBusy: Bool {
        isRefreshing || isAuthenticating || isInstallingCLI
    }

    var connectionStateTitle: String {
        switch connectionState {
        case .checking:
            return "Checking Codex CLI"
        case .ready:
            return "Codex CLI connected"
        case .authenticationRequired:
            return "Codex CLI authentication required"
        case .cliNotInstalled:
            return "Codex CLI is not installed"
        case .installing:
            return "Installing Codex CLI"
        case .authenticating:
            return "Waiting for browser authorization"
        case .failed:
            return "Codex CLI error"
        }
    }

    var connectionStateDetail: String? {
        switch connectionState {
        case .cliNotInstalled:
            let base = "ChatGPT Desktop with Codex does not provide CLI access for this app."
            guard let connectionMessage else { return base }
            return "\(connectionMessage)\nManual install: \(CodexCLIInstaller.manualInstallCommand)"
        case .authenticationRequired:
            let base = "Sign in to Codex CLI with your ChatGPT account."
            guard let connectionMessage else { return base }
            return "\(base)\n\(connectionMessage)"
        case .installing:
            return "Downloading the official installer and checking the user installation."
        case .authenticating:
            return "Complete the sign-in in your browser."
        case .failed:
            return connectionMessage
        case .checking, .ready:
            return nil
        }
    }

    var connectionActionTitle: String? {
        switch connectionState {
        case .authenticationRequired:
            return "Authorize"
        case .cliNotInstalled:
            return "Install Codex CLI"
        default:
            return nil
        }
    }

    var connectionActionIcon: String {
        connectionState == .cliNotInstalled ? "arrow.down.circle" : "person.badge.key"
    }

    var showsConnectionStatus: Bool {
        switch connectionState {
        case .checking, .ready:
            return false
        case .authenticationRequired, .cliNotInstalled, .installing, .authenticating, .failed:
            return true
        }
    }

    private func handleRefreshFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let knownState: CodexConnectionState?

        if let rateLimitError = error as? CodexRateLimitError {
            switch rateLimitError {
            case .codexNotFound:
                knownState = .cliNotInstalled
            case .authenticationRequired:
                knownState = .authenticationRequired
            case .timeout, .missingCodexLimit, .invalidWindow:
                knownState = nil
            }
        } else {
            knownState = nil
        }

        connectionState = knownState ?? .failed
        connectionMessage = knownState == nil ? message : nil
        lastCLIErrorMessage = message
        lastCLIErrorAt = Date()

        if var current = snapshot {
            current.errorMessage = knownState == nil ? message : nil
            snapshot = current
            do {
                try LimitStore.write(current)
            } catch {
                LimitLog.store.error("LimitStore.write failed: \(error.localizedDescription)")
            }
            reloadWidgets()
        }
    }

    func updatePreferences(_ update: (inout LimitPreferences) -> Void) {
        var next = preferences
        update(&next)
        preferences = next
        do {
            try LimitPreferencesStore.write(next)
        } catch {
            LimitLog.store.error("LimitPreferencesStore.write failed: \(error.localizedDescription)")
        }
        reloadWidgets()
    }

    // MARK: - Low limit alerts, per window

    func lowLimitAlertsEnabled(for window: LowLimitAlertWindow) -> Bool {
        preferences.lowLimitAlertsEnabled(for: window)
    }

    /// Turning a window on asks for system authorization first and only then
    /// stores the setting, so the switch never claims alerts that cannot be
    /// delivered. Turning it off is immediate.
    func setLowLimitAlertsEnabled(_ isEnabled: Bool, for window: LowLimitAlertWindow) {
        guard isEnabled else {
            updatePreferences { $0.setLowLimitAlertsEnabled(false, for: window) }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard await lowLimitNotificationManager.requestAuthorization() else { return }
            updatePreferences { $0.setLowLimitAlertsEnabled(true, for: window) }
            if let snapshot {
                await lowLimitNotificationManager.deliverIfNeeded(for: snapshot, preferences: preferences)
            }
        }
    }

    func lowLimitThresholds(for window: LowLimitAlertWindow) -> [Int?] {
        preferences.lowLimitThresholds(for: window)
    }

    func canAddLowLimitThreshold(for window: LowLimitAlertWindow) -> Bool {
        lowLimitThresholds(for: window).count < LimitPreferences.maximumNotificationThresholds
    }

    func canRemoveLowLimitThreshold(for window: LowLimitAlertWindow) -> Bool {
        !lowLimitThresholds(for: window).isEmpty
    }

    func addLowLimitThreshold(for window: LowLimitAlertWindow) {
        updatePreferences { preferences in
            var thresholds = preferences.lowLimitThresholds(for: window)
            guard thresholds.count < LimitPreferences.maximumNotificationThresholds else { return }
            let last = thresholds.reversed().compactMap { $0 }.first ?? 5
            thresholds.append(min(100, last + 5))
            preferences.setLowLimitThresholds(thresholds, for: window)
        }
    }

    func removeLastLowLimitThreshold(for window: LowLimitAlertWindow) {
        updatePreferences { preferences in
            var thresholds = preferences.lowLimitThresholds(for: window)
            guard !thresholds.isEmpty else { return }
            thresholds.removeLast()
            preferences.setLowLimitThresholds(thresholds, for: window)
        }
    }

    /// Writes one threshold field. `index` beyond the current list appends,
    /// and an empty field is stored as nil so the editor can hold blank rows.
    func setLowLimitNotificationThreshold(
        _ value: Int?,
        at index: Int,
        for window: LowLimitAlertWindow
    ) {
        updatePreferences { preferences in
            var thresholds = preferences.lowLimitThresholds(for: window)
            while thresholds.count <= index {
                thresholds.append(nil)
            }
            thresholds[index] = value
            preferences.setLowLimitThresholds(thresholds, for: window)
        }
    }

    func removeEmptyLowLimitThresholds(for window: LowLimitAlertWindow) {
        let compacted = lowLimitThresholds(for: window).compactMap { $0 }
        guard compacted.count != lowLimitThresholds(for: window).count else { return }
        updatePreferences { $0.setLowLimitThresholds(compacted, for: window) }
    }

    // MARK: - Diagnostics

    /// Where the displayed limits come from. The app never reads a cached
    /// third-party service; every successful sync goes through the local CLI.
    var dataSourceDescription: String {
        "Codex CLI (codex app-server --stdio, account/rateLimits/read)"
    }

    /// Formatted time of the last successful sync, or nil before the first one.
    var lastSyncText: String? {
        guard let lastSuccessfulSyncAt else { return nil }
        return formattedDiagnosticsDate(lastSuccessfulSyncAt)
    }

    /// Last CLI/app-server failure in the current app language, with its time.
    var lastErrorText: String? {
        guard let lastCLIErrorMessage, !lastCLIErrorMessage.isEmpty else { return nil }
        guard let lastCLIErrorAt else { return lastCLIErrorMessage }
        return "\(formattedDiagnosticsDate(lastCLIErrorAt)): \(lastCLIErrorMessage)"
    }

    private func formattedDiagnosticsDate(_ date: Date) -> String {
        let locale = preferences.appLanguage.locale
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = locale.identifier.lowercased().hasPrefix("ru") ? "d MMM, HH:mm" : "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Local data reset

    /// Removes only this app's local data: stored snapshot, preferences, widget
    /// payload, and notification history. The Codex account, CLI installation,
    /// and CLI authentication are never touched.
    func resetLocalAppData() async {
        dataGeneration += 1

        LimitStore.removeStoredSnapshot()
        LimitPreferencesStore.removeStoredPreferences()
        WidgetPayloadStore.removeStoredPayload()
        await lowLimitNotificationManager.resetHistory()

        snapshot = nil
        preferences = .default
        lastSuccessfulSyncAt = nil
        lastCLIErrorMessage = nil
        lastCLIErrorAt = nil
        connectionMessage = nil
        connectionState = .checking

        reloadWidgets()
    }

    var menuBarTitle: String {
        guard let snapshot, !hidesCurrentMenuBarMetric else { return "Codex --" }

        switch preferences.menuBarMode {
        case .detailed:
            if let creditsText = detailedMenuBarCreditValue {
                return creditsText
            }

            var parts: [String] = []
            if let fiveHour = snapshot.fiveHour {
                parts.append("5H \(menuBarValue(for: fiveHour))")
            }
            if let weekly = snapshot.weekly {
                parts.append("7D \(menuBarValue(for: weekly))")
            }
            return parts.isEmpty ? "Codex --" : parts.joined(separator: " ")
        case .percentOnly:
            return compactMenuBarValue
        }
    }

    private var detailedMenuBarCreditValue: String? {
        guard let snapshot,
              let creditsText = snapshot.credits?.displayText(maxFractionDigits: 4),
              (snapshot.fiveHour?.usedPercent ?? 0) >= 100 ||
              (snapshot.weekly?.usedPercent ?? 0) >= 100
        else {
            return nil
        }

        return creditsText
    }

    private func menuBarValue(for window: LimitWindowSnapshot) -> String {
        if window.usedPercent >= 100,
           let creditsText = snapshot?.credits?.displayText(maxFractionDigits: 2) {
            return creditsText
        }

        return "\(window.leftPercent)%"
    }

    var compactMenuBarValue: String {
        guard let snapshot, !hidesCurrentMenuBarMetric else { return "—" }

        let window: LimitWindowSnapshot?
        switch preferences.compactMenuBarMetric {
        case .fiveHour:
            window = snapshot.fiveHour ?? snapshot.weekly
        case .weekly:
            window = snapshot.weekly ?? snapshot.fiveHour
        }

        guard let window else { return "0%" }
        return menuBarValue(for: window)
    }

    var compactMenuBarPercent: Int {
        guard let snapshot, !hidesCurrentMenuBarMetric else { return 0 }

        switch preferences.compactMenuBarMetric {
        case .fiveHour:
            return (snapshot.fiveHour ?? snapshot.weekly)?.leftPercent ?? 0
        case .weekly:
            return (snapshot.weekly ?? snapshot.fiveHour)?.leftPercent ?? 0
        }
    }

    var availableCompactMenuBarMetrics: [MenuBarCompactMetric] {
        guard let snapshot else { return [] }
        return availableCompactMenuBarMetrics(for: snapshot)
    }

    private func availableCompactMenuBarMetrics(for snapshot: LimitSnapshot) -> [MenuBarCompactMetric] {
        var metrics: [MenuBarCompactMetric] = []
        if snapshot.fiveHour != nil {
            metrics.append(.fiveHour)
        }
        if snapshot.weekly != nil {
            metrics.append(.weekly)
        }
        return metrics
    }

    private func normalizeCompactMenuBarMetric(for snapshot: LimitSnapshot) {
        let availableMetrics = availableCompactMenuBarMetrics(for: snapshot)
        guard !availableMetrics.contains(preferences.compactMenuBarMetric),
              let fallbackMetric = availableMetrics.first
        else { return }

        preferences.compactMenuBarMetric = fallbackMetric
        do {
            try LimitPreferencesStore.write(preferences)
        } catch {
            LimitLog.store.error("LimitPreferencesStore.write failed: \(error.localizedDescription)")
        }
    }

    private var hidesCurrentMenuBarMetric: Bool {
        switch connectionState {
        case .authenticationRequired, .cliNotInstalled, .installing, .authenticating:
            return true
        case .checking, .ready, .failed:
            return false
        }
    }

    private func configureLoginItem() {
        if #available(macOS 13.0, *) {
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: loginItemSetupKey) else { return }

            #if DEBUG
            let isDebugBuild = true
            #else
            let isDebugBuild = false
            #endif

            guard LoginItemRegistrationPolicy.shouldRegister(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                bundleURL: Bundle.main.bundleURL,
                isDebugBuild: isDebugBuild
            ) else { return }

            let service = SMAppService.mainApp
            guard service.status == .notRegistered else {
                defaults.set(true, forKey: loginItemSetupKey)
                return
            }

            // Existing installations have already passed their first launch.
            // Do not register them again when an update leaves SMAppService in
            // a transient `notRegistered` state.
            guard !LimitPreferencesStore.hasStoredPreferences,
                  !LimitStore.hasStoredSnapshot else {
                defaults.set(true, forKey: loginItemSetupKey)
                return
            }

            do {
                try service.register()
            } catch {
                LimitLog.update.error("SMAppService.register failed: \(error.localizedDescription)")
            }
            defaults.set(true, forKey: loginItemSetupKey)
        }
    }

    private func configureSystemNotificationsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: notificationSetupKey) else { return }

        Task { [weak self] in
            guard let self else { return }
            let isAuthorized = await lowLimitNotificationManager.requestAuthorization()
            updatePreferences { preferences in
                for window in LowLimitAlertWindow.allCases {
                    preferences.setLowLimitAlertsEnabled(isAuthorized, for: window)
                }
            }
            UserDefaults.standard.set(true, forKey: notificationSetupKey)
        }
    }

    /// Compares two snapshots without the stamps that every successful poll
    /// refreshes so an unchanged reading does not trigger a widget reload.
    private static func contentChanged(from old: LimitSnapshot?, to new: LimitSnapshot) -> Bool {
        guard var previous = old else { return true }
        previous.updatedAt = new.updatedAt
        var candidate = new
        if previous.usage != nil, candidate.usage != nil {
            // Only a change of the usage freshness reaches the screen; a fresh
            // timestamp on the same numbers does not.
            guard previous.usage?.isStale == candidate.usage?.isStale else { return true }
            previous.usage?.updatedAt = nil
            candidate.usage?.updatedAt = nil
        }
        return previous != candidate
    }

    private func widgetReloadIsDue() -> Bool {
        guard let lastWidgetReloadAt else { return true }
        return Date().timeIntervalSince(lastWidgetReloadAt) >= Self.widgetReloadInterval
    }

    private func publishSnapshot() {
        widgetBridge.publish(WidgetPayload(snapshot: snapshot, preferences: preferences))
    }

    private func reloadWidgetTimelines() {
        lastWidgetReloadAt = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindIdentifier)
    }

    private func reloadWidgets() {
        publishSnapshot()
        reloadWidgetTimelines()
    }
}

private actor LowLimitNotificationManager {
    private struct LimitWindowCycle: Codable, Equatable {
        let kind: LowLimitAlertWindow
        let resetAtQuarterHour: Int64
    }

    private struct NotificationDelivery: Codable {
        let cycle: LimitWindowCycle
        let threshold: Int
        let deliveredAt: Date
    }

    private struct DeliveryLedger: Codable {
        var deliveries: [NotificationDelivery] = []
        // Keep the old string keys while users upgrade from 1.2.0. They stop
        // the same alert from being sent twice during the current reset cycle.
        var legacyDeliveryKeys: Set<String> = []
        // Reset cycle (quarter-hour index) in which a limit was last seen
        // depleted, keyed by window kind. A later, different cycle means the
        // limit came back and a restoration alert is due once per cycle.
        var depletedCycles: [String: Int64] = [:]
        var restoredCycles: [String: Int64] = [:]

        private enum CodingKeys: String, CodingKey {
            case deliveries
            case deliveredKeys
            case depletedCycles
            case restoredCycles
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deliveries = try container.decodeIfPresent([NotificationDelivery].self, forKey: .deliveries) ?? []
            legacyDeliveryKeys = try container.decodeIfPresent(Set<String>.self, forKey: .deliveredKeys) ?? []
            depletedCycles = try container.decodeIfPresent([String: Int64].self, forKey: .depletedCycles) ?? [:]
            restoredCycles = try container.decodeIfPresent([String: Int64].self, forKey: .restoredCycles) ?? [:]
        }

        func contains(_ cycle: LimitWindowCycle, threshold: Int, legacyKey: String?) -> Bool {
            deliveries.contains { $0.cycle == cycle && $0.threshold == threshold }
                || legacyKey.map { legacyDeliveryKeys.contains($0) } == true
        }

        mutating func record(_ cycle: LimitWindowCycle, threshold: Int, deliveredAt: Date) {
            deliveries.append(NotificationDelivery(cycle: cycle, threshold: threshold, deliveredAt: deliveredAt))
        }

        func depletedCycle(for kind: LowLimitAlertWindow) -> Int64? {
            depletedCycles[kind.rawValue]
        }

        mutating func recordDepleted(for kind: LowLimitAlertWindow, cycleAtQuarterHour: Int64) {
            depletedCycles[kind.rawValue] = cycleAtQuarterHour
        }

        mutating func clearDepleted(for kind: LowLimitAlertWindow) {
            depletedCycles.removeValue(forKey: kind.rawValue)
        }

        func didRestore(for kind: LowLimitAlertWindow, cycleAtQuarterHour: Int64) -> Bool {
            restoredCycles[kind.rawValue] == cycleAtQuarterHour
        }

        mutating func recordRestored(for kind: LowLimitAlertWindow, cycleAtQuarterHour: Int64) {
            restoredCycles[kind.rawValue] = cycleAtQuarterHour
        }

        mutating func removeExpiredEntries(now: Date) {
            // A weekly cycle can remain active for seven days. Retain completed
            // cycles for 30 days so partial API responses cannot erase history.
            let cutoff = Int64(now.addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970 / 900)
            deliveries.removeAll { $0.cycle.resetAtQuarterHour < cutoff }
            restoredCycles = restoredCycles.filter { $0.value >= cutoff }
            depletedCycles = depletedCycles.filter { $0.value >= cutoff }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(deliveries, forKey: .deliveries)
            try container.encode(legacyDeliveryKeys, forKey: .deliveredKeys)
            try container.encode(depletedCycles, forKey: .depletedCycles)
            try container.encode(restoredCycles, forKey: .restoredCycles)
        }
    }

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        default:
            return false
        }
    }

    /// Authorization check that never raises the system prompt.
    private func hasNotificationAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }

    /// Clears this app's notification history: the delivery ledger plus any
    /// notifications the app already posted or scheduled. Both are app-owned:
    /// the ledger is this app's file in Application Support and
    /// `UNUserNotificationCenter.current()` is scoped to this app's bundle.
    func resetHistory() async {
        try? FileManager.default.removeItem(at: ledgerURL())
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func deliverIfNeeded(for snapshot: LimitSnapshot, preferences: LimitPreferences) async {
        let sendsRestorationAlerts = preferences.restorationNotificationsEnabled
        // Each window keeps its own switch, so authorization and delivery are
        // decided per window rather than by one shared flag.
        let alertWindows = LowLimitAlertWindow.allCases.filter { preferences.lowLimitAlertsEnabled(for: $0) }
        guard !alertWindows.isEmpty || sendsRestorationAlerts else { return }

        // Only the low-limit toggle may raise the system prompt. Restoration
        // alerts reuse an authorization the user already granted.
        let isAuthorized = alertWindows.isEmpty
            ? await hasNotificationAuthorization()
            : await requestAuthorization()
        guard isAuthorized else { return }

        let now = Date()
        // Quiet hours suppress low-limit alerts only; a limit that came back is
        // still worth reporting, so restoration alerts are never held back.
        let suppressLowLimitAlerts = preferences.isQuietHoursActive(at: now)

        var ledger = readLedger()
        ledger.removeExpiredEntries(now: now)
        let windows: [(LowLimitAlertWindow, LimitWindowSnapshot)] = [
            snapshot.fiveHour.map { (.fiveHour, $0) },
            snapshot.weekly.map { (.weekly, $0) }
        ].compactMap { $0 }

        for (kind, window) in windows {
            guard let cycle = cycle(for: window, kind: kind) else { continue }
            let isDepleted = window.usedPercent >= 100

            if !isDepleted, let depletedCycle = ledger.depletedCycle(for: kind), depletedCycle != cycle.resetAtQuarterHour {
                if sendsRestorationAlerts, !ledger.didRestore(for: kind, cycleAtQuarterHour: cycle.resetAtQuarterHour) {
                    if await deliverRestorationNotification(
                        for: window,
                        kind: kind,
                        cycleAtQuarterHour: cycle.resetAtQuarterHour,
                        preferences: preferences
                    ) {
                        ledger.recordRestored(for: kind, cycleAtQuarterHour: cycle.resetAtQuarterHour)
                        ledger.clearDepleted(for: kind)
                    }
                } else {
                    ledger.clearDepleted(for: kind)
                }
            }

            if isDepleted {
                ledger.recordDepleted(for: kind, cycleAtQuarterHour: cycle.resetAtQuarterHour)
            }

            guard preferences.lowLimitAlertsEnabled(for: kind), !suppressLowLimitAlerts else { continue }

            // Several thresholds can match if the app first sees an already-low
            // value. Alert only for the nearest one; lower thresholds can still
            // alert later as the remaining percentage continues to fall.
            guard let threshold = preferences.lowLimitThresholds(for: kind)
                .compactMap({ $0 })
                .filter({ window.leftPercent <= $0 })
                .min()
            else { continue }

            let legacyKey = legacyDeliveryKey(for: window, threshold: threshold)
            guard !ledger.contains(cycle, threshold: threshold, legacyKey: legacyKey) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Codex limit is running low"
            content.body = "\(window.label): \(window.leftPercent)% remaining (alert threshold \(threshold)%)."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "codex-limit.\(kind.rawValue).\(cycle.resetAtQuarterHour).\(threshold)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                ledger.record(cycle, threshold: threshold, deliveredAt: Date())
            } catch {
                continue
            }
        }
        writeLedger(ledger)
    }

    /// Sends the once-per-cycle "limit is available again" alert in the app language.
    private func deliverRestorationNotification(
        for window: LimitWindowSnapshot,
        kind: LowLimitAlertWindow,
        cycleAtQuarterHour: Int64,
        preferences: LimitPreferences
    ) async -> Bool {
        let isRussian = preferences.appLanguage.locale.identifier.lowercased().hasPrefix("ru")
        let windowName: String
        switch kind {
        case .fiveHour:
            windowName = isRussian ? "5 часов" : "5 hours"
        case .weekly:
            windowName = isRussian ? "Неделя" : "Week"
        }

        let content = UNMutableNotificationContent()
        content.title = isRussian ? "Лимит Codex восстановлен" : "Codex limit restored"
        content.body = isRussian
            ? "\(windowName): лимит сброшен, снова доступно \(window.leftPercent)%."
            : "\(windowName): the limit reset and \(window.leftPercent)% is available again."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "codex-limit.restored.\(kind.rawValue).\(cycleAtQuarterHour)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func cycle(for window: LimitWindowSnapshot, kind: LowLimitAlertWindow) -> LimitWindowCycle? {
        guard let resetsAt = window.resetsAt else { return nil }
        // The API can shift a reset timestamp by seconds between refreshes.
        // Rounding to 15-minute buckets keeps one real reset cycle stable.
        let resetAtQuarterHour = Int64((resetsAt.timeIntervalSince1970 / 900).rounded())
        return LimitWindowCycle(kind: kind, resetAtQuarterHour: resetAtQuarterHour)
    }

    private func legacyDeliveryKey(for window: LimitWindowSnapshot, threshold: Int) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let resetHour = Int(resetsAt.timeIntervalSince1970 / 3_600)
        return "\(window.windowDurationMins ?? 0)-\(resetHour)|\(threshold)"
    }

    private func readLedger() -> DeliveryLedger {
        let url = ledgerURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DeliveryLedger()
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.codexLimitDecoder.decode(DeliveryLedger.self, from: data)
        } catch {
            LimitLog.store.error("Notification ledger read failed: \(error.localizedDescription)")
            return DeliveryLedger()
        }
    }

    private func writeLedger(_ ledger: DeliveryLedger) {
        let data: Data
        do {
            data = try JSONEncoder.codexLimitEncoder.encode(ledger)
        } catch {
            LimitLog.store.error("Notification ledger encode failed: \(error.localizedDescription)")
            return
        }
        let url = ledgerURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            LimitLog.store.error("Notification ledger write failed: \(error.localizedDescription)")
        }
    }

    private func ledgerURL() -> URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("CodexLimitWidget", isDirectory: true)
            .appendingPathComponent("low-limit-notification-ledger.json")
    }
}

private final class LoopbackWidgetBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sergeylopukhov.codexlimitwidget.loopback")
    private var listener: NWListener?
    private var responseData = Data()

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 38347)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            listener = nil
        }
    }

    func publish(_ payload: WidgetPayload) {
        let data = (try? JSONEncoder.codexLimitEncoder.encode(payload)) ?? Data()
        queue.sync { responseData = data }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let isPayloadRequest = request.hasPrefix("GET /v1/widget-payload ")
            let body = isPayloadRequest ? self.responseData : Data()
            let status = isPayloadRequest ? "200 OK" : "404 Not Found"
            let headers = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
