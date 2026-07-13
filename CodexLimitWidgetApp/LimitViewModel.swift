import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class LimitViewModel: ObservableObject {
    @Published private(set) var snapshot: LimitSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var preferences: LimitPreferences

    private let client = CodexRateLimitClient()
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

    private func configureLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKindIdentifier)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
