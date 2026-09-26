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

            case .suspended(let reason):
                SuspendedView(reason: reason)
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
        Tokens.bg.ignoresSafeArea()
    }
}

private struct OrphanedView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        DarsEmpty(title: L("orphaned_title"), body_: L("orphaned_body")) {
            MotionButton(title: LocalizedStringKey(L("common_sign_out")), destructive: true) {
                Task { await auth.signOut() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg.ignoresSafeArea())
    }
}

private struct SuspendedView: View {
    let reason: String?
    @Environment(AuthStore.self) private var auth

    var body: some View {
        let text = (reason?.isEmpty == false) ? L("suspended_body_reason", reason!) : L("suspended_body")
        DarsEmpty(title: L("suspended_title"), body_: text) {
            MotionButton(title: LocalizedStringKey(L("common_sign_out")), destructive: true) {
                Task { await auth.signOut() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg.ignoresSafeArea())
    }
}
