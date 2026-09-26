import SwiftUI

struct Skeleton: View {
    var width: CGFloat?
    var height: CGFloat = 16
    var radius: CGFloat = Metrics.Radius.sm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DarsColor.labelTertiary)
            .opacity(reduceMotion ? 0.28 : (breathing ? 0.42 : 0.18))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: breathing
            )
            .onAppear { breathing = true }
            .accessibilityHidden(true)
    }
}

struct DarsEmptyState<Action: View>: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    var systemImage: String = "tray"
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: Metrics.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DarsColor.labelTertiary)

            Text(title)
                .darsType(.title3)
                .foregroundStyle(DarsColor.labelPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .darsType(.subheadline)
                    .foregroundStyle(DarsColor.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            action
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.Space.xl)
        .padding(.vertical, Metrics.Space.huge)
        .accessibilityElement(children: .combine)
    }
}

extension DarsEmptyState where Action == EmptyView {
    init(title: LocalizedStringKey,
         message: LocalizedStringKey? = nil,
         systemImage: String = "tray") {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}

struct DarsErrorState: View {
    let message: Text
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Metrics.Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(DarsColor.danger)

            Text("state.error.title")
                .darsType(.title3)
                .foregroundStyle(DarsColor.labelPrimary)

            message
                .darsType(.subheadline)
                .foregroundStyle(DarsColor.labelSecondary)
                .multilineTextAlignment(.center)

            if let retry {
                DarsButton(title: "common.retry", kind: .secondary) {
                    retry()
                }
                .padding(.top, Metrics.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.Space.xl)
        .padding(.vertical, Metrics.Space.xxl)
    }
}

#Preview("States") {
    ScrollView {
        VStack(spacing: Metrics.Space.xl) {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                Skeleton(width: 160, height: 22)
                Skeleton()
                Skeleton()
            }
            .padding(.horizontal, Metrics.Space.lg)

            DarsEmptyState(
                title: "state.empty.title",
                systemImage: "tray"
            )

            DarsErrorState(message: Text(verbatim: "Cannot reach Dars.")) {}
        }
    }
    .background(DarsColor.backgroundBase)
}
