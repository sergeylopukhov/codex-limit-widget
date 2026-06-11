import SwiftUI

struct LimitGaugeView: View {
    let window: LimitWindowSnapshot
    var compact: Bool = false
    var showsResetTime: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: compact ? 10 : 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.dimText)
                Spacer()
                Text("\(window.leftPercent)%")
                    .font(.system(size: compact ? 15 : 24, weight: .black, design: .monospaced))
                    .foregroundStyle(Self.accent)
                    .lineLimit(1)
            }

            TerminalPopupMeter(percent: window.leftPercent, color: Self.accent)

            if showsResetTime {
                Text("Reset: \(window.resetText)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.dimText)
                    .lineLimit(1)
            }
        }
    }

    private static let accent = Color(red: 0.52, green: 0.95, blue: 0.43)
    private static let dimText = Color(red: 0.64, green: 0.86, blue: 0.58)
}

struct SnapshotDetailView: View {
    let snapshot: LimitSnapshot?
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Codex limits")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer()
                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }
            TerminalPopupDivider(color: mutedAccent)

            if let snapshot {
                LimitGaugeView(window: snapshot.fiveHour, compact: true)
                LimitGaugeView(window: snapshot.weekly, compact: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Updated: \(Self.dateTimeFormatter.string(from: snapshot.updatedAt))")
                    if let planType = snapshot.planType {
                        Text("Plan: \(planType)")
                    }
                    if snapshot.isStale {
                        Text("Data is older than 5 minutes")
                            .foregroundStyle(.orange)
                    }
                    if let errorMessage = snapshot.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.32))
                            .lineLimit(3)
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("> no limit data")
                    Text("> refresh to load Codex limits")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(dimText)
            }
        }
        .padding(14)
        .frame(width: 286, alignment: .topLeading)
        .background(TerminalPopupBackground())
    }

    private let accent = Color(red: 0.52, green: 0.95, blue: 0.43)
    private let mutedAccent = Color(red: 0.32, green: 0.56, blue: 0.28)
    private let dimText = Color(red: 0.64, green: 0.86, blue: 0.58)

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter
    }()
}

private struct TerminalPopupMeter: View {
    let percent: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.13))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .shadow(color: color.opacity(0.28), radius: 3)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, percent))) / 100)
            }
        }
        .frame(height: 7)
    }
}

private struct TerminalPopupDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.75))
            .frame(height: 1)
    }
}

private struct TerminalPopupBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.105),
                        Color(red: 0.015, green: 0.018, blue: 0.015)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
