import WidgetKit
import SwiftUI

private final class TimelineCompletionBox<Value>: @unchecked Sendable {
    let completion: (Value) -> Void

    init(_ completion: @escaping (Value) -> Void) {
        self.completion = completion
    }
}

struct CodexLimitEntry: TimelineEntry {
    let date: Date
    let snapshot: LimitSnapshot?
    let preferences: LimitPreferences
}

struct CodexLimitProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexLimitEntry {
        CodexLimitEntry(date: Date(), snapshot: .placeholder, preferences: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexLimitEntry) -> Void) {
        let completionBox = TimelineCompletionBox(completion)
        Task {
            let payload = await loadPayload() ?? WidgetPayload(snapshot: .placeholder, preferences: .default)
            completionBox.completion(CodexLimitEntry(date: Date(), snapshot: payload.snapshot, preferences: payload.preferences))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexLimitEntry>) -> Void) {
        let completionBox = TimelineCompletionBox(completion)
        Task {
            let payload = await loadPayload() ?? WidgetPayloadStore.read()
            let snapshot = payload?.snapshot
            let preferences = payload?.preferences ?? .default
            let now = Date()
            // Hold the same reading across four entries so the widget keeps a
            // stable value between the app's conditional reloads.
            let entries = (0..<4).map { step in
                let offset = TimeInterval(step * 5 * 60)
                let date = Calendar.current.date(byAdding: .minute, value: step * 5, to: now) ?? now.addingTimeInterval(offset)
                return CodexLimitEntry(date: date, snapshot: snapshot, preferences: preferences)
            }
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(15 * 60)
            completionBox.completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    private func loadPayload() async -> WidgetPayload? {
        if let payload = await WidgetBridgeClient.fetch() {
            WidgetPayloadStore.write(payload)
            return payload
        }
        return nil
    }
}
