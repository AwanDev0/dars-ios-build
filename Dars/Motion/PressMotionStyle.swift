import SwiftUI

private struct PressBody: ViewModifier {
    let pressed: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (pressed ? scale : 1))
            .opacity(reduceMotion ? (pressed ? 0.72 : 1) : 1)
            .animation(Motion.press, value: pressed)
    }
}

private extension View {
    func pressBody(_ pressed: Bool, _ scale: CGFloat) -> some View {
        modifier(PressBody(pressed: pressed, scale: scale))
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .pressBody(configuration.isPressed, Motion.Scale.row)
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .pressBody(configuration.isPressed, Motion.Scale.card)
    }
}

struct ButtonPressStyle: ButtonStyle {
    var haptic: HapticEngine.Event? = .selection

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .pressBody(configuration.isPressed, Motion.Scale.button)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed, let haptic { HapticEngine.play(haptic) }
            }
    }
}

struct PrimaryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .pressBody(configuration.isPressed, Motion.Scale.primary)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { HapticEngine.play(.impactLight) }
            }
    }
}

struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .pressBody(configuration.isPressed, Motion.Scale.icon)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { HapticEngine.play(.selection) }
            }
    }
}

extension ButtonStyle where Self == RowPressStyle {
    static var darsRow: RowPressStyle { RowPressStyle() }
}
extension ButtonStyle where Self == CardPressStyle {
    static var darsCard: CardPressStyle { CardPressStyle() }
}
extension ButtonStyle where Self == ButtonPressStyle {
    static var darsButton: ButtonPressStyle { ButtonPressStyle() }
}
extension ButtonStyle where Self == PrimaryPressStyle {
    static var darsPrimary: PrimaryPressStyle { PrimaryPressStyle() }
}
extension ButtonStyle where Self == IconPressStyle {
    static var darsIcon: IconPressStyle { IconPressStyle() }
}
