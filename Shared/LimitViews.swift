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
    var design: MenuWindowDesign = .terminal
    let refresh: () -> Void

    @ViewBuilder
    var body: some View {
        switch design {
        case .terminal, .system:
            TerminalSnapshotDetailView(
                snapshot: snapshot,
                isRefreshing: isRefreshing,
                refresh: refresh
            )
        case .editorial:
            EditorialSnapshotDetailView(
                snapshot: snapshot,
                isRefreshing: isRefreshing,
                refresh: refresh
            )
        }
    }
}

private struct TerminalSnapshotDetailView: View {
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
                if let fiveHour = snapshot.fiveHour {
                    LimitGaugeView(window: fiveHour, compact: true)
                }
                if let weekly = snapshot.weekly {
                    LimitGaugeView(window: weekly, compact: true)
                    Text("Weekly reset: \(weekly.resetDateTimeText)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(dimText)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 3) {
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

}

private struct EditorialSnapshotDetailView: View {
    let snapshot: LimitSnapshot?
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Limit")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(MenuWindowVisuals.editorialInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(MenuWindowVisuals.editorialInk)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MenuWindowVisuals.editorialInk)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }

            EditorialPopupDivider()

            if let snapshot, let metric = snapshot.fiveHour ?? snapshot.weekly {
                let metricLabel = snapshot.fiveHour == nil ? "WEEK" : "5 HOURS"
                let metricResetLabel = snapshot.fiveHour == nil ? "WEEK RESET" : "5H RESET"
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: -5) {
                        Text("\(metric.leftPercent)%")
                            .font(.system(size: 50, weight: .regular, design: .serif))
                            .foregroundStyle(MenuWindowVisuals.editorialInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)

                        Text("Remaining")
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(MenuWindowVisuals.editorialInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .layoutPriority(2)

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 4) {
                        editorialCompactStat(metricResetLabel, metric.resetText)
                        editorialCompactStat("PLAN", (snapshot.planType ?? "--").uppercased())
                    }
                    .padding(.top, 5)
                }

                EditorialPopupMeter(title: metricLabel, percent: metric.leftPercent)
                if let weekly = snapshot.weekly, snapshot.fiveHour != nil {
                    EditorialPopupMeter(title: "WEEK", percent: weekly.leftPercent)
                }

                HStack(spacing: 10) {
                    editorialCompactStat("USED", "\(metric.usedPercent)%")
                    if let weekly = snapshot.weekly, snapshot.fiveHour != nil {
                        EditorialPopupVerticalRule()
                        editorialCompactStat("WEEKLY", "\(weekly.leftPercent)%")
                    }
                }

                if let weekly = snapshot.weekly {
                    editorialWeeklyReset(weekly.resetDateTimeText)
                }

                if snapshot.isStale {
                    Text("Data is older than 5 minutes")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.31, blue: 0.16))
                        .lineLimit(1)
                }

                if let errorMessage = snapshot.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.16, blue: 0.14))
                        .lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No limit data")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(MenuWindowVisuals.editorialInk)
                    Text("Waiting for sync")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(MenuWindowVisuals.editorialMutedInk)
                }
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .center)
            }
        }
        .padding(14)
        .frame(width: 286, alignment: .topLeading)
        .background(EditorialPopupBackground())
    }

    private func editorialCompactStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(MenuWindowVisuals.editorialMutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(MenuWindowVisuals.editorialInk)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorialWeeklyReset(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WEEKLY RESET")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(MenuWindowVisuals.editorialMutedInk)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(MenuWindowVisuals.editorialInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

private struct EditorialPopupMeter: View {
    let title: String
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text("\(percent)% REMAINING")
            }
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(MenuWindowVisuals.editorialMutedInk)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MenuWindowVisuals.editorialEmpty.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(MenuWindowVisuals.editorialRule.opacity(0.72), lineWidth: 1)
                        )

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MenuWindowVisuals.editorialFill)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, percent))) / 100)
                }
            }
            .frame(height: 6)
            .clipped()
        }
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

private struct EditorialPopupDivider: View {
    var body: some View {
        Rectangle()
            .fill(MenuWindowVisuals.editorialRule.opacity(0.72))
            .frame(height: 1)
    }
}

private struct EditorialPopupVerticalRule: View {
    var body: some View {
        Rectangle()
            .fill(MenuWindowVisuals.editorialRule.opacity(0.72))
            .frame(width: 1, height: 26)
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

private struct EditorialPopupBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(MenuWindowVisuals.editorialPaper)

            LinearGradient(
                colors: [
                    MenuWindowVisuals.editorialPaperLight.opacity(0.82),
                    MenuWindowVisuals.editorialPaper.opacity(0.38),
                    MenuWindowVisuals.editorialFill.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

enum MenuWindowVisuals {
    static let terminalAccent = Color(red: 0.52, green: 0.95, blue: 0.43)
    static let terminalBackground = Color(red: 0.02, green: 0.025, blue: 0.022)
    static let terminalBorder = Color(red: 0.52, green: 0.95, blue: 0.43).opacity(0.22)

    static let editorialPaper = Color(red: 0.93, green: 0.90, blue: 0.82)
    static let editorialPaperLight = Color(red: 0.98, green: 0.96, blue: 0.90)
    static let editorialInk = Color(red: 0.14, green: 0.14, blue: 0.12)
    static let editorialMutedInk = Color(red: 0.43, green: 0.39, blue: 0.31)
    static let editorialRule = Color(red: 0.74, green: 0.68, blue: 0.57)
    static let editorialFill = Color(red: 0.54, green: 0.50, blue: 0.39)
    static let editorialEmpty = Color(red: 0.90, green: 0.86, blue: 0.77)

    static func popoverBackground(for design: MenuWindowDesign) -> Color {
        switch design {
        case .terminal, .system:
            return terminalBackground
        case .editorial:
            return editorialPaper
        }
    }

    static func popoverBorder(for design: MenuWindowDesign) -> Color {
        switch design {
        case .terminal, .system:
            return terminalBorder
        case .editorial:
            return editorialRule.opacity(0.52)
        }
    }

    static func settingsForeground(for design: MenuWindowDesign) -> Color {
        switch design {
        case .terminal, .system:
            return terminalAccent
        case .editorial:
            return editorialInk
        }
    }

    static func separator(for design: MenuWindowDesign) -> Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.09, green: 0.10, blue: 0.09)
        case .editorial:
            return editorialRule.opacity(0.7)
        }
    }

    static func settingsFont(for design: MenuWindowDesign) -> Font {
        switch design {
        case .terminal, .system:
            return .system(size: 13, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 15, weight: .regular, design: .serif)
        }
    }
}
