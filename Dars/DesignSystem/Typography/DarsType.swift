import SwiftUI

enum DarsType {
    enum Script {
        case latin
        case arabic

        var sizeMultiplier: CGFloat { self == .arabic ? 1.06 : 1.0 }
        var lineSpacingRatio: CGFloat { self == .arabic ? 0.32 : 0.18 }
    }

    enum Role {
        case largeTitle, title1, title2, title3
        case headline, body, callout, subheadline
        case footnote, caption

        var size: CGFloat {
            switch self {
            case .largeTitle:   return 34
            case .title1:       return 28
            case .title2:       return 22
            case .title3:       return 20
            case .headline:     return 17
            case .body:         return 17
            case .callout:      return 16
            case .subheadline:  return 15
            case .footnote:     return 13
            case .caption:      return 12
            }
        }

        var weight: Font.Weight {
            switch self {
            case .largeTitle, .title1:  return .bold
            case .title2, .title3:      return .semibold
            case .headline:             return .semibold
            case .body, .callout:       return .regular
            case .subheadline:          return .medium
            case .footnote, .caption:   return .medium
            }
        }

        var latinTracking: CGFloat {
            switch self {
            case .largeTitle:   return -0.4
            case .title1:       return -0.3
            case .title2:       return -0.2
            default:            return 0
            }
        }

        var textStyle: Font.TextStyle {
            switch self {
            case .largeTitle:   return .largeTitle
            case .title1:       return .title
            case .title2:       return .title2
            case .title3:       return .title3
            case .headline:     return .headline
            case .body:         return .body
            case .callout:      return .callout
            case .subheadline:  return .subheadline
            case .footnote:     return .footnote
            case .caption:      return .caption
            }
        }
    }
}

extension DarsType {
    static func tracking(_ role: Role, script: Script) -> CGFloat {
        script == .arabic ? 0 : role.latinTracking
    }
}

private struct DarsScriptKey: EnvironmentKey {
    static let defaultValue: DarsType.Script = .latin
}

extension EnvironmentValues {
    var darsScript: DarsType.Script {
        get { self[DarsScriptKey.self] }
        set { self[DarsScriptKey.self] = newValue }
    }
}

private struct DarsTypeModifier: ViewModifier {
    let role: DarsType.Role

    @Environment(\.darsScript) private var script

    @ScaledMetric private var scaledSize: CGFloat

    init(role: DarsType.Role) {
        self.role = role
        _scaledSize = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        let size = scaledSize * script.sizeMultiplier
        return content
            .font(.system(size: size, weight: role.weight))
            .fontDesign(.default)
            .tracking(DarsType.tracking(role, script: script))
            .lineSpacing(size * script.lineSpacingRatio)
    }
}

extension View {
    func darsType(_ role: DarsType.Role) -> some View {
        modifier(DarsTypeModifier(role: role))
    }

    func darsScript(_ script: DarsType.Script) -> some View {
        environment(\.darsScript, script)
    }
}

enum Metrics {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 26
    }

    static func concentric(_ parent: CGFloat, padding: CGFloat) -> CGFloat {
        max(4, parent - padding)
    }

    static let minimumTouchTarget: CGFloat = 44
}
