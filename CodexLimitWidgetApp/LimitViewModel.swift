import Foundation
import Network
import ServiceManagement
import WidgetKit

@MainActor
final class LimitViewModel: ObservableObject {
    @Published private(set) var snapshot: LimitSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var preferences: LimitPreferences

    private let client = CodexRateLimitClient()
    private let widgetBridge = LoopbackWidgetBridge()
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
        WidgetCenter.shared.reloadAllTimelines()
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
