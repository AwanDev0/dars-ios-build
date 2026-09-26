import SwiftUI

enum DarsButtonKind {
    case primary
    case secondary
    case destructive
    case plain
}

struct DarsButton: View {
    let title: LocalizedStringKey
    var kind: DarsButtonKind = .primary
    var systemImage: String?
    var isLoading: Bool = false
    var fullWidth: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            action()
        }) {
            ZStack {
                content
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: Metrics.minimumTouchTarget)
            .padding(.horizontal, kind == .plain ? Metrics.Space.sm : Metrics.Space.lg)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(style)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
        .accessibilityValue(
            isLoading
                ? Text("common.inProgress")
                : Text("")
        )
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }

    @ViewBuilder private var content: some View {
        HStack(spacing: Metrics.Space.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
            }
            Text(title)
                .darsType(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, Metrics.Space.sm)
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                .fill(DarsColor.accent)
        case .secondary:
            RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                .fill(DarsColor.accentSoft)
        case .destructive:
            RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                .fill(DarsColor.danger.opacity(0.12))
        case .plain:
            Color.clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return DarsColor.onAccent
        case .secondary: return DarsColor.accentLabel
        case .destructive: return DarsColor.danger
        case .plain: return DarsColor.accentLabel
        }
    }

    private var style: some ButtonStyle {
        kind == .primary ? AnyDarsStyle(PrimaryPressStyle()) : AnyDarsStyle(ButtonPressStyle())
    }
}

private struct AnyDarsStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

struct DarsIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = Metrics.Icon.medium
    var tint: Color = DarsColor.labelPrimary
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isDestructive ? DarsColor.danger : tint)
                .darsHitTarget()
        }
        .buttonStyle(.darsIcon)
        .accessibilityLabel(accessibilityLabel)
    }
}
