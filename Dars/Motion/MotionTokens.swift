import SwiftUI

enum Motion {
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.86)

    static let arrive = Animation.spring(response: 0.34, dampingFraction: 0.72)

    static let moment = Animation.spring(response: 0.55, dampingFraction: 0.68)

    static let sheet = Animation.spring(response: 0.32, dampingFraction: 0.84)

    static let decelerate = Animation.timingCurve(0.0, 0.0, 0.2, 1.0, duration: 0.30)

    static let accelerate = Animation.timingCurve(0.4, 0.0, 1.0, 1.0, duration: 0.22)

    static let symmetric = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.26)

    static let selection = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.18)

    static let theme = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.55)

    enum Scale {
        static let row: CGFloat = 0.985
        static let card: CGFloat = 0.98
        static let button: CGFloat = 0.97
        static let primary: CGFloat = 0.965
        static let icon: CGFloat = 0.94
        static let bubble: CGFloat = 0.985
    }
}
