import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(OpeningState.self) private var opening

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                RestoringView()

            case .signedOut:
                LoginView()
                    .transition(.opacity)

            case .signedIn(let profile):
                ShellView(profile: profile)
                    .transition(.opacity)

            case .orphaned:
                OrphanedView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.symmetric, value: auth.state)
        .task { auth.start() }
        .onChange(of: auth.state, initial: true) { _, now in
            if now != .restoring { opening.resolved = true }
        }
        .onChange(of: auth.profile?.id) { _, id in
            PushRegistrar.shared.sessionChanged(signedIn: id != nil)
        }
    }
}

private struct RestoringView: View {
    var body: some View {
        ZStack {
            DarsColor.backgroundBase.ignoresSafeArea()
            Text("Dars")
                .darsType(.largeTitle)
                .foregroundStyle(DarsColor.labelTertiary)
        }
    }
}

private struct OrphanedView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(spacing: Metrics.Space.xl) {
            ContentUnavailableView(
                "orphaned.title",
                systemImage: "building.2.crop.circle.badge.questionmark",
                description: Text("orphaned.body")
            )
            Button("common.signOut") {
                Task { await auth.signOut() }
            }
            .buttonStyle(.darsButton)
            .foregroundStyle(DarsColor.danger)
        }
        .padding(Metrics.Space.lg)
        .background(DarsColor.backgroundBase)
    }
}
