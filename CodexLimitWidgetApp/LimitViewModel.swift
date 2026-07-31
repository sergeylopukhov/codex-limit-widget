import Foundation
import Network
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

    private let client = CodexRateLimitClient()
    private let widgetBridge = LoopbackWidgetBridge()
    private let lowLimitNotificationManager = LowLimitNotificationManager()
    private let notificationSetupKey = "systemNotificationsConfigured"
    private let loginItemSetupKey = "loginItemRegistrationCompleted"
    private var timer: Timer?
    private var started = false

    init() {
        snapshot = LimitStore.read()
        preferences = LimitPreferencesStore.read()
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

    func refresh() async {
        guard !isRefreshing, !isAuthenticating, !isInstallingCLI else { return }
        isRefreshing = true
        connectionState = .checking
        connectionMessage = nil
        defer { isRefreshing = false }

        do {
            var fresh = try await client.fetch()
            if fresh.usage == nil {
                fresh.usage = snapshot?.usage
            }
            normalizeCompactMenuBarMetric(for: fresh)
            snapshot = fresh
            try? LimitStore.write(fresh)
            reloadWidgets()
            await lowLimitNotificationManager.deliverIfNeeded(for: fresh, preferences: preferences)
            connectionState = .ready
        } catch {
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

        if var current = snapshot {
            current.errorMessage = knownState == nil ? message : nil
            snapshot = current
            try? LimitStore.write(current)
            reloadWidgets()
        }
    }

    func updatePreferences(_ update: (inout LimitPreferences) -> Void) {
        var next = preferences
        update(&next)
        preferences = next
        try? LimitPreferencesStore.write(next)
        reloadWidgets()
    }

    func setLowLimitNotificationsEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            updatePreferences { $0.lowLimitNotificationsEnabled = false }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard await lowLimitNotificationManager.requestAuthorization() else { return }
            updatePreferences { $0.lowLimitNotificationsEnabled = true }
            if let snapshot {
                await lowLimitNotificationManager.deliverIfNeeded(for: snapshot, preferences: preferences)
            }
        }
    }

    func addNotificationThreshold() {
        updatePreferences { preferences in
            guard preferences.lowLimitNotificationThresholds.count < 5 else { return }
            let last = preferences.lowLimitNotificationThresholds.reversed().compactMap { $0 }.first ?? 5
            preferences.lowLimitNotificationThresholds.append(min(100, last + 5))
            preferences.lowLimitNotificationThresholds = LimitPreferences.normalizedNotificationThresholds(
                preferences.lowLimitNotificationThresholds
            )
        }
    }

    func removeLastNotificationThreshold() {
        updatePreferences { preferences in
            guard !preferences.lowLimitNotificationThresholds.isEmpty else { return }
            preferences.lowLimitNotificationThresholds.removeLast()
        }
    }

    func removeEmptyNotificationThresholds() {
        let compacted = preferences.lowLimitNotificationThresholds.compactMap { $0 }
        guard compacted.count != preferences.lowLimitNotificationThresholds.count else { return }
        updatePreferences { $0.lowLimitNotificationThresholds = compacted }
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
        try? LimitPreferencesStore.write(preferences)
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

            try? service.register()
            defaults.set(true, forKey: loginItemSetupKey)
        }
    }

    private func configureSystemNotificationsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: notificationSetupKey) else { return }

        Task { [weak self] in
            guard let self else { return }
            let isAuthorized = await lowLimitNotificationManager.requestAuthorization()
            updatePreferences { preferences in
                preferences.lowLimitNotificationsEnabled = isAuthorized
            }
            UserDefaults.standard.set(true, forKey: notificationSetupKey)
        }
    }

    private func reloadWidgets() {
        widgetBridge.publish(WidgetPayload(snapshot: snapshot, preferences: preferences))
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindIdentifier)
    }
}

private actor LowLimitNotificationManager {
    private enum LimitWindowKind: String, Codable {
        case fiveHour
        case weekly
    }

    private struct LimitWindowCycle: Codable, Equatable {
        let kind: LimitWindowKind
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

        private enum CodingKeys: String, CodingKey {
            case deliveries
            case deliveredKeys
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deliveries = try container.decodeIfPresent([NotificationDelivery].self, forKey: .deliveries) ?? []
            legacyDeliveryKeys = try container.decodeIfPresent(Set<String>.self, forKey: .deliveredKeys) ?? []
        }

        func contains(_ cycle: LimitWindowCycle, threshold: Int, legacyKey: String?) -> Bool {
            deliveries.contains { $0.cycle == cycle && $0.threshold == threshold }
                || legacyKey.map { legacyDeliveryKeys.contains($0) } == true
        }

        mutating func record(_ cycle: LimitWindowCycle, threshold: Int, deliveredAt: Date) {
            deliveries.append(NotificationDelivery(cycle: cycle, threshold: threshold, deliveredAt: deliveredAt))
        }

        mutating func removeExpiredEntries(now: Date) {
            // A weekly cycle can remain active for seven days. Retain completed
            // cycles for 30 days so partial API responses cannot erase history.
            let cutoff = Int64(now.addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970 / 900)
            deliveries.removeAll { $0.cycle.resetAtQuarterHour < cutoff }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(deliveries, forKey: .deliveries)
            try container.encode(legacyDeliveryKeys, forKey: .deliveredKeys)
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

    func deliverIfNeeded(for snapshot: LimitSnapshot, preferences: LimitPreferences) async {
        guard preferences.lowLimitNotificationsEnabled,
              await requestAuthorization()
        else { return }

        var ledger = readLedger()
        ledger.removeExpiredEntries(now: Date())
        let windows: [(LimitWindowKind, LimitWindowSnapshot)] = [
            snapshot.fiveHour.map { (.fiveHour, $0) },
            snapshot.weekly.map { (.weekly, $0) }
        ].compactMap { $0 }

        for (kind, window) in windows {
            guard let cycle = cycle(for: window, kind: kind) else { continue }
            // Several thresholds can match if the app first sees an already-low
            // value. Alert only for the nearest one; lower thresholds can still
            // alert later as the remaining percentage continues to fall.
            guard let threshold = preferences.lowLimitNotificationThresholds
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

    private func cycle(for window: LimitWindowSnapshot, kind: LimitWindowKind) -> LimitWindowCycle? {
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
        guard let data = try? Data(contentsOf: ledgerURL()),
              let ledger = try? JSONDecoder.codexLimitDecoder.decode(DeliveryLedger.self, from: data)
        else { return DeliveryLedger() }
        return ledger
    }

    private func writeLedger(_ ledger: DeliveryLedger) {
        guard let data = try? JSONEncoder.codexLimitEncoder.encode(ledger) else { return }
        let url = ledgerURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
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
