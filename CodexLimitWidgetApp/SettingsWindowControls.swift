import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
@preconcurrency import UserNotifications

extension LowLimitAlertWindow {
    var alertSwitchTitle: String {
        switch self {
        case .fiveHour:
            "5-hour alerts"
        case .weekly:
            "Weekly alerts"
        }
    }

    var thresholdTitle: String {
        switch self {
        case .fiveHour:
            "5-hour thresholds"
        case .weekly:
            "Weekly thresholds"
        }
    }
}

struct NotificationThresholdEditor: View {
    @ObservedObject var viewModel: LimitViewModel
    let window: LowLimitAlertWindow
    let palette: SettingsWindowPalette

    var body: some View {
        SettingsRow(window.thresholdTitle, palette: palette) {
            HStack(spacing: 6) {
                if viewModel.canRemoveLowLimitThreshold(for: window) {
                    Button {
                        viewModel.removeLastLowLimitThreshold(for: window)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.backgroundHighlight)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(palette.rule, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove last alert threshold")
                }

                ForEach(Array(viewModel.lowLimitThresholds(for: window).indices), id: \.self) { index in
                    SettingsThresholdField(
                        text: thresholdBinding(at: index),
                        palette: palette
                    )
                }

                if viewModel.canAddLowLimitThreshold(for: window) {
                    Button {
                        viewModel.addLowLimitThreshold(for: window)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.backgroundHighlight)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(palette.rule, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add alert threshold")
                }
            }
        }
    }

    private func thresholdBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                let thresholds = viewModel.lowLimitThresholds(for: window)
                return index < thresholds.count ? thresholds[index].map(String.init) ?? "" : ""
            },
            set: { value in
                viewModel.setLowLimitNotificationThreshold(
                    value.isEmpty ? nil : Int(value),
                    at: index,
                    for: window
                )
            }
        )
    }
}

struct SettingsThresholdField: View {
    @Binding var text: String
    let palette: SettingsWindowPalette
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text("%").foregroundStyle(palette.mutedText)
        )
        .textFieldStyle(.plain)
        .font(palette.controlFont)
        .foregroundStyle(palette.primaryText)
        .multilineTextAlignment(.center)
        .focused($isFocused)
        .padding(.horizontal, 6)
        .frame(width: 42, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.backgroundHighlight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? palette.accent : palette.rule, lineWidth: isFocused ? 1.5 : 1)
        )
        .accessibilityLabel("Alert threshold")
    }
}

struct SettingsWindowPalette {
    let design: MenuWindowDesign

    var background: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.02, green: 0.026, blue: 0.022)
        case .editorial:
            return MenuWindowVisuals.editorialPaper
        }
    }

    var backgroundHighlight: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.11, green: 0.14, blue: 0.10)
        case .editorial:
            return MenuWindowVisuals.editorialPaperLight
        }
    }

    var titleText: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialInk
        }
    }

    var primaryText: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.69, green: 0.91, blue: 0.64)
        case .editorial:
            return MenuWindowVisuals.editorialInk
        }
    }

    var mutedText: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.44, green: 0.62, blue: 0.40)
        case .editorial:
            return MenuWindowVisuals.editorialMutedInk
        }
    }

    var accent: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialFill
        }
    }

    var accentText: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.025, green: 0.035, blue: 0.025)
        case .editorial:
            return MenuWindowVisuals.editorialPaperLight
        }
    }

    var controlTrack: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.09, green: 0.12, blue: 0.085)
        case .editorial:
            return MenuWindowVisuals.editorialEmpty
        }
    }

    var controlSelected: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalAccent
        case .editorial:
            return MenuWindowVisuals.editorialFill
        }
    }

    var rule: Color {
        switch design {
        case .terminal, .system:
            return Color(red: 0.29, green: 0.48, blue: 0.25).opacity(0.58)
        case .editorial:
            return MenuWindowVisuals.editorialRule.opacity(0.72)
        }
    }

    var border: Color {
        switch design {
        case .terminal, .system:
            return MenuWindowVisuals.terminalBorder
        case .editorial:
            return MenuWindowVisuals.editorialRule.opacity(0.54)
        }
    }

    var titleFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 21, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 24, weight: .regular, design: .serif)
        }
    }

    var sectionFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 16, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 19, weight: .semibold)
        }
    }

    var labelFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 13, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 16, weight: .medium)
        }
    }

    var controlFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 12, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 15, weight: .medium)
        }
    }

    var noteFont: Font {
        switch design {
        case .terminal, .system:
            return .system(size: 11, weight: .bold, design: .monospaced)
        case .editorial:
            return .system(size: 13, weight: .regular)
        }
    }
}

struct SettingsWindowBackground: View {
    let palette: SettingsWindowPalette

    var body: some View {
        ZStack {
            Rectangle()
                .fill(palette.background)

            LinearGradient(
                colors: [
                    palette.backgroundHighlight.opacity(0.92),
                    palette.background.opacity(0.78),
                    palette.accent.opacity(palette.design == .terminal ? 0.10 : 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct SettingsTitleBar: View {
    let design: MenuWindowDesign
    let palette: SettingsWindowPalette
    @State private var showsWindowButtonSymbols = false

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                SettingsWindowButton(command: .close, showsSymbol: showsWindowButtonSymbols)
                SettingsWindowButton(command: .minimize, showsSymbol: showsWindowButtonSymbols)
                SettingsWindowButton(command: .zoom, showsSymbol: showsWindowButtonSymbols)
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    showsWindowButtonSymbols = isHovering
                }
            }

            Text("Codex Limit Widget Settings")
                .font(palette.titleFont)
                .foregroundStyle(palette.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 12)

            Text(design == .terminal ? "DARK" : "BEIGE")
                .font(palette.noteFont)
                .foregroundStyle(palette.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .contentShape(Rectangle())
    }
}

enum SettingsWindowCommand {
    case close
    case minimize
    case zoom

    var color: Color {
        switch self {
        case .close:
            return Color(red: 1.00, green: 0.32, blue: 0.34)
        case .minimize:
            return Color(red: 1.00, green: 0.74, blue: 0.06)
        case .zoom:
            return Color(red: 0.18, green: 0.78, blue: 0.32)
        }
    }

    var symbolName: String {
        switch self {
        case .close:
            return "xmark"
        case .minimize:
            return "minus"
        case .zoom:
            return "arrow.up.left.and.arrow.down.right"
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .close, .minimize:
            return 7.5
        case .zoom:
            return 6.5
        }
    }

    @MainActor
    func perform() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        switch self {
        case .close:
            window.close()
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.zoom(nil)
        }
    }
}

struct SettingsWindowButton: View {
    let command: SettingsWindowCommand
    let showsSymbol: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            command.perform()
        } label: {
            ZStack {
                Circle()
                    .fill(command.color)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.6)
                    )

                Image(systemName: command.symbolName)
                    .font(.system(size: command.symbolSize, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(showsSymbol ? 1 : 0)
            }
            .frame(width: 13, height: 13)
            .scaleEffect(isHovering ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: showsSymbol)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct SettingsSectionTitle: View {
    let title: String
    let palette: SettingsWindowPalette

    init(_ title: String, palette: SettingsWindowPalette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(palette.sectionFont)
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let palette: SettingsWindowPalette
    @ViewBuilder let control: () -> Control

    init(_ title: String, palette: SettingsWindowPalette, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.palette = palette
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(LocalizedStringKey(title))
                .font(palette.labelFont)
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 14)

            control()
        }
        .frame(minHeight: 32)
    }
}

struct SettingsRule: View {
    let palette: SettingsWindowPalette

    var body: some View {
        Rectangle()
            .fill(palette.rule)
            .frame(height: 1)
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool
    let palette: SettingsWindowPalette

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? palette.accent : palette.controlTrack)
                .frame(width: 54, height: 28)
                .overlay(
                    Circle()
                        .fill(isOn ? palette.accentText : palette.backgroundHighlight)
                        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                        .frame(width: 22, height: 22)
                        .offset(x: isOn ? 13 : -13)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(palette.rule.opacity(isOn ? 0.0 : 0.9), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct SettingsTimePicker: View {
    @Binding var minutes: Int
    let palette: SettingsWindowPalette

    var body: some View {
        DatePicker(
            "",
            selection: Binding(
                get: { Self.date(fromMinutes: minutes) },
                set: { minutes = LimitPreferences.normalizedMinutesOfDay(Self.minutes(from: $0)) }
            ),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .datePickerStyle(.field)
        .font(palette.controlFont)
        .foregroundStyle(palette.primaryText)
        .frame(width: 104)
        .accessibilityLabel("Time of day")
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

struct SettingsSegmentedItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

struct SettingsSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [SettingsSegmentedItem<Value>]
    let palette: SettingsWindowPalette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = selection == item.value

                SettingsSegmentedOption(
                    title: item.title,
                    isSelected: isSelected,
                    palette: palette
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = item.value
                    }
                }
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(palette.controlTrack)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(palette.rule.opacity(0.65), lineWidth: 1)
        )
    }
}

struct SettingsSegmentedOption: View {
    let title: String
    let isSelected: Bool
    let palette: SettingsWindowPalette
    let action: () -> Void

    var body: some View {
        let foreground = isSelected ? palette.accentText : palette.primaryText
        let background = isSelected ? palette.controlSelected : Color.clear

        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(palette.controlFont)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 14)
                .frame(minWidth: 76)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let palette: SettingsWindowPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(LocalizedStringKey(title))
                    .font(palette.controlFont)
            }
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.accent.opacity(isDisabled ? 0.45 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
