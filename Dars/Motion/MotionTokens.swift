import SwiftUI

enum Motion {
    static func spring(damping ratio: Double, stiffness k: Double) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: k, damping: 2 * ratio * k.squareRoot(), initialVelocity: 0)
    }

    static let press = spring(damping: 1.03, stiffness: 500)
    static let arrive = spring(damping: 0.87, stiffness: 260)
    static let tab = spring(damping: 1.0, stiffness: 400)
    static let micro = spring(damping: 0.96, stiffness: 350)
    static let moment = spring(damping: 0.92, stiffness: 200)
    static let gesture = spring(damping: 1.0, stiffness: 500)
    static let listPlacement = spring(damping: 1.0, stiffness: 200)
    static let sheet = tab

    static let instant = Animation.timingCurve(0.45, 0.0, 0.55, 1.0, duration: 0.10)
    static let standard = Animation.timingCurve(0.45, 0.0, 0.55, 1.0, duration: 0.20)
    static let emphasis = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.35)
    static let expressive = Animation.timingCurve(0.16, 1.0, 0.30, 1.0, duration: 0.35)

    static let decelerate = emphasis
    static let accelerate = Animation.timingCurve(0.55, 0.0, 1.0, 0.45, duration: 0.20)
    static let symmetric = standard
    static let selection = standard
    static let theme = Animation.timingCurve(0.45, 0.0, 0.55, 1.0, duration: 0.55)

    enum Scale {
        static let row: CGFloat = 0.985
        static let card: CGFloat = 0.98
        static let button: CGFloat = 0.97
        static let primary: CGFloat = 0.965
        static let icon: CGFloat = 0.94
        static let bubble: CGFloat = 0.985
        static let chip: CGFloat = 0.96
    }

    static let minTouchTarget: CGFloat = 48
}
