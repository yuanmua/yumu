import AppKit
import SwiftUI

/// Localised string from the Bark translation source (generated into Resources/).
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .module)
}

extension Bark {
    typealias RGBA = (Double, Double, Double, Double)

    /// A colour that follows the window appearance, built from the light and dark token values.
    static func dynamic(light: RGBA, dark: RGBA) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: value.3)
        })
    }
}

extension View {
    /// Bark animation that becomes instant when the system asks to reduce motion.
    func barkAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation, value: value)
    }

    /// A white card with a hairline border: the container for every grouped list.
    func insetCard() -> some View {
        background(Bark.Colors.surfaceDefault, in: RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous).strokeBorder(Bark.Colors.borderSubtle))
    }

    func hairlineBelow() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1) }
    }
}

// MARK: Buttons

/// The one accent-filled button of a page.
struct PrimaryButtonStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .system(size: 15, weight: .semibold) : .system(size: 13, weight: .medium))
            .foregroundStyle(Bark.Colors.textOnAccent)
            .padding(.horizontal, large ? 26 : 14)
            .frame(height: large ? 44 : 30)
            .frame(minWidth: large ? 150 : 0)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: large ? Bark.Radius.md : Bark.Radius.sm, style: .continuous))
            .shadow(color: Color.accentColor.opacity(large ? 0.3 : 0), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .barkAnimation(Bark.Motion.quick, value: configuration.isPressed)
    }
}

/// Everything that is not the primary action.
struct SecondaryButtonStyle: ButtonStyle {
    var large = false
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .system(size: 14, weight: .medium) : .system(size: 13, weight: .medium))
            .foregroundStyle(danger ? Bark.Colors.statusDanger : Bark.Colors.textPrimary)
            .padding(.horizontal, large ? 18 : 12)
            .frame(height: large ? 44 : 30)
            .background(
                danger ? Bark.Colors.statusDanger.opacity(0.12) : Bark.Colors.surfaceElevated,
                in: RoundedRectangle(cornerRadius: large ? Bark.Radius.md : Bark.Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? Bark.Radius.md : Bark.Radius.sm, style: .continuous)
                    .strokeBorder(danger ? Color.clear : Bark.Colors.borderSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? Bark.Radius.md : Bark.Radius.sm, style: .continuous)
                    .fill(Bark.Colors.surfaceHover)
                    .opacity(configuration.isPressed ? 1 : 0)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .barkAnimation(Bark.Motion.quick, value: configuration.isPressed)
    }
}

/// Text-only button in the accent colour, for low-priority inline actions.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Bark.Colors.surfaceHover.opacity(configuration.isPressed ? 1 : 0), in: RoundedRectangle(cornerRadius: Bark.Radius.sm, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryLarge: PrimaryButtonStyle { PrimaryButtonStyle(large: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var secondaryLarge: SecondaryButtonStyle { SecondaryButtonStyle(large: true) }
    static var danger: SecondaryButtonStyle { SecondaryButtonStyle(danger: true) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: Small pieces

/// A small rounded label: version numbers, loader names, states.
struct Tag: View {
    enum Tone { case neutral, accent, success, warning, danger }
    let text: String
    var tone = Tone.neutral
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(foreground.opacity(tone == .neutral ? 0.08 : 0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Bark.Colors.textSecondary
        case .accent: Color.accentColor
        case .success: Bark.Colors.statusSuccess
        case .warning: Bark.Colors.statusWarning
        case .danger: Bark.Colors.statusDanger
        }
    }
}

/// The running-state dot; breathes unless motion is reduced.
struct StatusDot: View {
    var color = Bark.Colors.statusSuccess
    var breathing = true
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard breathing, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Underline tabs with optional counts (the Forest tab bar).
struct UnderlineTabs<ID: Hashable>: View {
    struct Item { let id: ID; let title: String; var count: Int? }
    let items: [Item]
    @Binding var selection: ID
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.id) { item in
                Button {
                    withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Bark.Motion.standard) { selection = item.id }
                } label: {
                    HStack(spacing: 6) {
                        Text(item.title)
                        if let count = item.count, count > 0 {
                            Text(String(count))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Bark.Colors.textTertiary)
                                .padding(.horizontal, 6)
                                .frame(height: 16)
                                .background(Bark.Colors.surfaceSunken, in: Capsule())
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selection == item.id ? Bark.Colors.textPrimary : Bark.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if selection == item.id {
                            RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(height: 2)
                                .matchedGeometryEffect(id: "underline", in: underline)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBelow()
    }
}

/// Title row of a card: icon, title, optional hint, trailing action.
struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var hint: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(icon: String, title: String, hint: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.hint = hint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Bark.Space.sm) {
            Image(systemName: icon).foregroundStyle(Bark.Colors.textSecondary).font(.system(size: 13))
            Text(title).font(.system(size: 14, weight: .semibold))
            if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary) }
            Spacer()
            trailing()
        }
        .padding(.horizontal, Bark.Space.lg)
        .frame(height: 48)
        .hairlineBelow()
    }
}

/// Settings-style row: title, optional description, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: () -> Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: Bark.Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary) }
            }
            Spacer(minLength: Bark.Space.lg)
            control()
        }
        .padding(.horizontal, Bark.Space.lg)
        .padding(.vertical, Bark.Space.md)
        .frame(minHeight: 52)
    }
}

/// Group of setting rows with a small uppercase heading.
struct SettingGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.sm) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Bark.Colors.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, Bark.Space.xs)
            }
            _VariadicView.Tree(DividedLayout()) { content() }
                .insetCard()
        }
    }
}

/// Puts a hairline between each child.
private struct DividedLayout: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
            }
        }
    }
}
