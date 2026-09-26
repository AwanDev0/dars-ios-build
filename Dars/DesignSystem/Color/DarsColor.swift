import SwiftUI
import UIKit

enum DarsColor {
    static var palette: DarsPalette { PaletteStore.shared.current }

    static let brandGold = dynamic(light: 0xFAB900, dark: 0xFAB900)

    static var accent: Color { dynamic(light: palette.accentLight, dark: palette.accentDark) }

    static var accentLabel: Color { dynamic(light: palette.accentTextLight, dark: palette.accentDark) }

    static var accentSoft: Color { dynamic(light: palette.accentLight, dark: palette.accentDark, lightAlpha: 0.16, darkAlpha: 0.14) }

    static var onAccent: Color { dynamic(light: palette.onAccentLight, dark: palette.onAccentDark) }

    static var action: Color { dynamic(light: palette.actionLight, dark: palette.actionDark) }

    static var backgroundBase: Color { dynamic(light: palette.lightBg, dark: palette.darkBg) }
    static var backgroundElevated: Color { dynamic(light: 0xFFFFFF, dark: palette.darkCard) }
    static var surface: Color { dynamic(light: 0xFFFFFF, dark: palette.darkCard) }
    static var surfaceGrouped: Color { dynamic(light: palette.lightCardAlt, dark: palette.darkCardAlt) }
    static var surfaceRaised: Color { dynamic(light: 0xFFFFFF, dark: palette.darkRaised) }

    static let labelPrimary = dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let labelSecondary = dynamicRGBA(
        light: (0, 0, 0, 0.56),
        dark:  (1, 1, 1, 0.62)
    )
    static let labelTertiary = dynamicRGBA(
        light: (0, 0, 0, 0.38),
        dark:  (1, 1, 1, 0.32)
    )

    static let separator = dynamicRGBA(
        light: (0.235, 0.235, 0.263, 0.10),
        dark:  (1, 1, 1, 0.07)
    )

    static let danger = dynamic(light: 0xD70015, dark: 0xFF3B30)
    static let warning = dynamic(light: 0xB25000, dark: 0xFF9500)
    static let success = dynamic(light: 0x15803D, dark: 0x34C759)

    static let glassTint = dynamicRGBA(
        light: (1, 1, 1, 0.62),
        dark:  (0.039, 0.039, 0.071, 0.48)
    )
    static let glassStroke = dynamicRGBA(
        light: (1, 1, 1, 0.82),
        dark:  (1, 1, 1, 0.16)
    )
    static let glassSpecular = dynamicRGBA(
        light: (1, 1, 1, 0.70),
        dark:  (0.902, 0.941, 1, 0.14)
    )

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }

    private static func dynamicRGBA(
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
