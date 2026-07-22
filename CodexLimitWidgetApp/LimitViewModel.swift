import Foundation
import Network
import ServiceManagement
@preconcurrency import UserNotifications
import WidgetKit

@MainActor
final class LimitViewModel: ObservableObject {
    @Published private(set) var snapshot: LimitSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var preferences: LimitPreferences

    private let client = CodexRateLimitClient()
    private let widgetBridge = LoopbackWidgetBridge()
    private let lowLimitNotificationManager = LowLimitNotificationManager()
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
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
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
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if var current = snapshot {
                current.errorMessage = message
                snapshot = current
                try? LimitStore.write(current)
                reloadWidgets()
            }
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
        guard let snapshot else { return "Codex --" }

        switch preferences.menuBarMode {
        case .detailed:
            var parts: [String] = []
            if let fiveHour = snapshot.fiveHour {
                parts.append("5H \(fiveHour.leftPercent)%")
            }
            if let weekly = snapshot.weekly {
                parts.append("7D \(weekly.leftPercent)%")
            }
            return parts.isEmpty ? "Codex --" : parts.joined(separator: " ")
        case .percentOnly:
            return "\(compactMenuBarPercent)%"
        }
    }

    var compactMenuBarPercent: Int {
        guard let snapshot else { return 0 }

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

    private func configureLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
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
