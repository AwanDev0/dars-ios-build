import SwiftUI

extension Metrics.Space {
    static let huge: CGFloat = 48
}

extension Metrics.Radius {
    static let bubble: CGFloat = 20
}

extension Metrics {
    static let comfortableTouchTarget: CGFloat = 52

    static let rowMinHeight: CGFloat = 48

    enum Icon {
        static let small: CGFloat = 15
        static let medium: CGFloat = 18
        static let large: CGFloat = 22
    }

    enum Avatar {
        static let small: CGFloat = 32
        static let medium: CGFloat = 40
        static let large: CGFloat = 64
    }
}

extension View {
    func darsScreenPadding() -> some View {
        padding(.horizontal, Metrics.Space.lg)
    }

    func darsHitTarget(_ size: CGFloat = Metrics.minimumTouchTarget) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}
