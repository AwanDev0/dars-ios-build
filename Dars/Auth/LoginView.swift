import SwiftUI

struct LoginView: View {
    @State private var forgot = false
    @Environment(AuthStore.self) private var auth
    @FocusState private var focus: Field?
    @State private var email = ""
    @State private var password = ""

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !auth.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.xl) {
                header

                VStack(spacing: Metrics.Space.md) {
                    field(
                        text: Binding(get: { email }, set: { email = $0; auth.clearError() }),
                        placeholder: "login.email",
                        symbol: "envelope",
                        field: .email
                    )
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                    field(
                        text: Binding(get: { password }, set: { password = $0; auth.clearError() }),
                        placeholder: "login.password",
                        symbol: "lock",
                        field: .password,
                        secure: true
                    )
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                }

                errorRow

                Button(action: submit) {
                    ZStack {
                        Text("login.signIn")
                            .darsType(.headline)
                            .opacity(auth.isWorking ? 0 : 1)
                        if auth.isWorking {
                            ProgressView().tint(DarsColor.onAccent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.darsPrimary)
                .background(
                    DarsColor.accent.opacity(canSubmit ? 1 : 0.4),
                    in: RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                )
                .foregroundStyle(DarsColor.onAccent)
                .disabled(!canSubmit)
                .animation(Motion.symmetric, value: canSubmit)

                otherDoors
            }
            .padding(Metrics.Space.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DarsColor.backgroundBase)
        .onAppear { HapticEngine.prepare() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            Text("Dars")
                .darsType(.largeTitle)
                .foregroundStyle(DarsColor.labelPrimary)
            Text("login.subtitle")
                .darsType(.subheadline)
                .foregroundStyle(DarsColor.labelSecondary)
        }
        .padding(.top, Metrics.Space.xxl)
        .padding(.bottom, Metrics.Space.sm)
    }

    @ViewBuilder
    private func field(
        text: Binding<String>,
        placeholder: LocalizedStringKey,
        symbol: String,
        field: Field,
        secure: Bool = false
    ) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(focus == field ? DarsColor.accent : DarsColor.labelTertiary)
                .frame(width: 20)
                .animation(Motion.selection, value: focus)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .darsType(.body)
            .foregroundStyle(DarsColor.labelPrimary)
            .focused($focus, equals: field)
        }
        .padding(.horizontal, Metrics.Space.lg)
        .frame(height: 52)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                .strokeBorder(
                    focus == field ? DarsColor.accent : DarsColor.separator,
                    lineWidth: focus == field ? 1.5 : 0.5
                )
                .animation(Motion.selection, value: focus)
        }
    }

    @ViewBuilder
    private var errorRow: some View {
        if let error = auth.error {
            HStack(alignment: .top, spacing: Metrics.Space.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                error.messageText
                    .darsType(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DarsColor.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(Motion.arrive, value: auth.error)
        }
    }

    private var otherDoors: some View {
        VStack(spacing: 4) {
            NavigationLink { StudentSignInView() } label: {
                Text("login.imAStudent")
                    .darsType(.subheadline).foregroundStyle(DarsColor.accentLabel)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            }
            .buttonStyle(.darsButton)

            NavigationLink { ParentSignUpView() } label: {
                Text("I'm a parent, new here")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            }
            .buttonStyle(.darsButton)

            Button { forgot = true } label: {
                Text("I've forgotten my password")
                    .darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $forgot) { ForgotPasswordView() }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task { await auth.signIn(email: email, password: password) }
    }
}
