import SwiftUI
import Combine

enum AuthRoute: Hashable {
    case student(String?)
    case parent(String?)
}

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(LanguageStore.self) private var language
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(OpeningState.self) private var opening

    @State private var path: [AuthRoute] = []
    @State private var delivered = false
    @State private var email = ""
    @State private var password = ""
    @State private var revealed = false
    @State private var tab = 0
    @State private var rememberMe = true
    @State private var askForgot = false
    @State private var scanning = false
    @State private var shake: CGFloat = 0
    @State private var keyboard = false
    @State private var whimsy: (Whimsy, Date)?

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !auth.isWorking
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                Tokens.bg.ignoresSafeArea()
                LoginBackdrop().ignoresSafeArea()
                LoginWhimsy(request: whimsy).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        LoginHeader(collapse: keyboard ? 1 : 0, delivered: delivered)
                            .frame(maxWidth: .infinity)
                        AuthCard {
                            MotionSegmentedControl(
                                options: [L("login_tab_signin"), L("login_tab_join")],
                                selected: Binding(get: { tab }, set: { new in hideKeyboard(); tab = new }),
                                emphasis: true,
                                height: 46,
                                corner: 22,
                                fontSize: 14.5
                            )
                            Spacer().frame(height: 20)
                            ZStack {
                                if tab == 0 {
                                    signInPanel
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(Motion.emphasis),
                                            removal: .opacity.animation(Motion.standard)
                                        ))
                                } else {
                                    joinPanel
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(Motion.emphasis),
                                            removal: .opacity.animation(Motion.standard)
                                        ))
                                }
                            }
                            .animation(Motion.emphasis, value: tab)
                        }
                        .darsEnter(delay: 0.33, rise: 36)
                        .offset(x: shake)

                        HStack(spacing: 6) {
                            MaterialIcon("Filled.Lock", size: 13).foregroundStyle(Tokens.textMuted)
                            Text(verbatim: L("login_trust")).font(.system(size: 12)).foregroundStyle(Tokens.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .darsEnter(delay: 0.33, rise: 20)
                        CreditLine(compact: true)
                            .padding(.bottom, 12)
                            .darsEnter(delay: 0.33, rise: 20)
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)

                HStack(spacing: 6) {
                    ThemeToggle(dark: scheme == .dark) {
                        settings.mode = scheme == .dark ? .light : .dark
                    }
                    LanguageSwitch(language: language.language) { language.set($0) }
                }
                .padding(.top, 14)
                .padding(.trailing, 10)
                .darsEnter(rise: 0)
            }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.openingCue, opening.cue)
            .onAppear { delivered = opening.playing }
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .student(let code): StudentSignInView(initialCode: code)
                case .parent(let code): ParentSignUpView(initialCode: code)
                }
            }
            .sheet(isPresented: $askForgot) {
                DarsSheet(title: L("login_forgot_title")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: L("login_forgot_body"))
                            .font(.system(size: 14.5))
                            .lineSpacing(6.5)
                            .foregroundStyle(Tokens.textSub)
                        MotionPrimaryButton(title: LocalizedStringKey(L("common_ok"))) { askForgot = false }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $scanning) {
                ScanCodeSheet { code in
                    let family = code.contains("family=1") || code.lowercased().hasPrefix("f")
                    let clean = JoinLink.code(from: code)
                    path.append(family ? .parent(clean) : .student(clean))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.timingCurve(0.17, 0.59, 0.40, 1.0, duration: 0.35)) { keyboard = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.timingCurve(0.17, 0.59, 0.40, 1.0, duration: 0.35)) { keyboard = false }
            }
            .onChange(of: auth.error) { _, error in
                guard error != nil, !auth.isWorking else { return }
                HapticEngine.play(.error)
                guard !reduce else { return }
                Task { @MainActor in
                    for x in [CGFloat(9), -7, 4, 0] {
                        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.07)) { shake = x }
                        try? await Task.sleep(for: .milliseconds(70))
                    }
                }
            }
            .onChange(of: email) { _, typed in
                if let kind = LoginWhimsy.request(for: typed) {
                    whimsy = (kind, Date())
                    HapticEngine.play(.success)
                }
            }
        }
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeading(title: L("login_welcome_back"), subtitle: L("login_welcome_sub"))
            AuthField(
                text: Binding(get: { email }, set: { email = $0; auth.clearError() }),
                icon: "Filled.MailOutline",
                label: L("login_email_hint"),
                placeholder: L("login_email_example"),
                keyboard: .emailAddress,
                content: .username,
                submit: .next
            )
            AuthField(
                text: Binding(get: { password }, set: { password = $0; auth.clearError() }),
                icon: "Filled.Lock",
                label: L("login_password_hint"),
                secure: true,
                revealed: revealed,
                content: .password,
                submit: .done,
                onSubmit: submit,
                onReveal: { HapticEngine.play(.selection); revealed.toggle() }
            )
            HStack {
                Button { rememberMe.toggle() } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(rememberMe ? Tokens.action : Tokens.well)
                            MaterialIcon("Filled.Check", size: 13)
                                .foregroundStyle(Tokens.onAction.opacity(rememberMe ? 1 : 0))
                                .scaleEffect(rememberMe ? 1 : 0.6)
                        }
                        .frame(width: 20, height: 20)
                        .animation(Motion.standard, value: rememberMe)
                        Text(verbatim: L("login_remember")).font(.system(size: 14, weight: .medium)).foregroundStyle(Tokens.text)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScalePress(scale: Motion.Scale.row))
                Spacer()
                Button { askForgot = true } label: {
                    HStack(spacing: 2) {
                        Text(verbatim: L("login_forgot")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.accentText)
                        MaterialIcon("AutoMirrored.Filled.KeyboardArrowRight", size: 16).foregroundStyle(Tokens.accentText)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScalePress(scale: Motion.Scale.button))
            }
            .padding(.top, 16)
            MessageLine(message: auth.error?.text, tone: .error)
                .padding(.bottom, auth.error == nil ? 0 : 12)
            ActionButton(title: L("login_sign_in"), enabled: canSubmit, working: auth.isWorking, action: submit)
        }
    }

    private var joinPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeading(title: L("login_join_title"), subtitle: L("login_join_sub"))
            VStack(spacing: 10) {
                JoinRow(index: 0, icon: "Filled.School", label: L("login_join_student"), sub: L("login_join_student_sub")) { path.append(.student(nil)) }
                JoinRow(index: 1, icon: "Filled.PeopleOutline", label: L("login_join_parent"), sub: L("login_join_parent_sub")) { path.append(.parent(nil)) }
                JoinRow(index: 2, icon: "Filled.QrCodeScanner", label: L("login_join_scan"), sub: L("login_join_scan_sub")) { scanning = true }
            }
            Reassure(icon: "Filled.HelpOutline", text: L("login_join_help"))
                .darsStagger(3, rise: 6)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        hideKeyboard()
        let typed = email.trimmingCharacters(in: .whitespaces)
        let secret = password
        Task { await auth.signIn(email: typed, password: secret) }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

enum JoinLink {
    static func code(from scanned: String) -> String {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "dars" || url.host?.contains("dars") == true {
            let last = url.pathComponents.last ?? trimmed
            return last.uppercased()
        }
        return trimmed.uppercased()
    }
}

private struct JoinRow: View {
    let index: Int
    let icon: String
    let label: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            EmptyView()
        }
        .buttonStyle(JoinRowStyle(icon: icon, label: label, sub: sub))
        .darsStagger(index)
    }
}

private struct JoinRowStyle: ButtonStyle {
    let icon: String
    let label: String
    let sub: String

    func makeBody(configuration: Configuration) -> some View {
        JoinRowBody(icon: icon, label: label, sub: sub, pressed: configuration.isPressed)
    }
}

private struct JoinRowBody: View {
    let icon: String
    let label: String
    let sub: String
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let press: CGFloat = pressed && !reduce ? 1 : 0
        HStack(spacing: 13) {
            MaterialIcon(icon, size: 19)
                .foregroundStyle(pressed ? Tokens.gold : Tokens.textSub)
                .frame(width: 42, height: 42)
                .background(Tokens.well, in: RR(13))
                .overlay(RR(13).strokeBorder(Tokens.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Tokens.text)
                Text(verbatim: sub).font(.system(size: 12.5)).lineSpacing(3.5).foregroundStyle(Tokens.textMuted).lineLimit(2)
            }
            Spacer(minLength: 0)
            MaterialIcon("AutoMirrored.Filled.KeyboardArrowRight", size: 17)
                .foregroundStyle(Tokens.textMuted)
                .offset(x: press * 3 * (direction == .rightToLeft ? -1 : 1))
        }
        .padding(13)
        .background(Tokens.card, in: RR(18))
        .overlay(RR(18).strokeBorder(pressed ? Tokens.gold.opacity(0.55) : Tokens.border, lineWidth: 1))
        .contentShape(RR(18))
        .scaleEffect(1 - 0.025 * press)
        .animation(Motion.press, value: pressed)
    }
}

private struct LoginHeader: View, Animatable {
    var collapse: CGFloat
    var delivered = false
    var animatableData: CGFloat {
        get { collapse }
        set { collapse = newValue }
    }
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { g in
            let c = collapse
            let width = g.size.width
            let markSize: CGFloat = 96
            let brandHeight: CGFloat = 44
            let tagHeight: CGFloat = 18
            let top: CGFloat = 56
            let markFull = CGPoint(x: width / 2, y: top + markSize / 2)
            let brandFull = CGPoint(x: width / 2, y: top + markSize + 16 + brandHeight / 2)
            let tagFull = CGPoint(x: width / 2, y: brandFull.y + brandHeight / 2 + 4 + tagHeight / 2)
            let rowMid: CGFloat = 4 + 28
            let markSmall = markSize * 40 / 96
            let brandSmallW: CGFloat = 70 * 22 / 36
            let rtl = direction == .rightToLeft
            let markCompact = CGPoint(x: rtl ? width - markSmall / 2 : markSmall / 2, y: rowMid)
            let brandCompact = CGPoint(x: rtl ? width - markSmall - 12 - brandSmallW / 2 : markSmall + 12 + brandSmallW / 2, y: rowMid)
            let tagCompact = CGPoint(x: width / 2, y: rowMid)
            ZStack {
                HeroMark(reportsFrame: true)
                    .scaleEffect(1 - (1 - 40.0 / 96.0) * c)
                    .position(mix(markFull, markCompact, c))
                    .modifier(DarsEnterHero(skip: delivered))
                (Text(verbatim: L("login_wordmark_a")) + Text(verbatim: L("login_wordmark_b")).foregroundColor(Tokens.gold))
                    .font(.system(size: 36, weight: .heavy))
                    .darsTracking(-1.4)
                    .foregroundStyle(Tokens.text)
                    .lineLimit(1)
                    .fixedSize()
                    .scaleEffect(1 - (1 - 22.0 / 36.0) * c)
                    .position(mix(brandFull, brandCompact, c))
                    .darsEnter(delay: 0.11)
                Text(verbatim: L("login_tagline"))
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSub)
                    .lineLimit(1)
                    .opacity(Double(min(max(1 - c * 1.6, 0), 1)))
                    .offset(y: -8 * c)
                    .position(mix(tagFull, tagCompact, c))
                    .darsEnter(delay: 0.22, rise: 8)
            }
        }
        .frame(height: (56 + 96 + 16 + 44 + 4 + 18 + 24) * (1 - collapse) + 60 * collapse)
    }

    private func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct DarsEnterHero: ViewModifier {
    var skip = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.openingCue) private var cue
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce || skip ? 1 : 0)
            .scaleEffect(shown || reduce || skip ? 1 : 0.88)
            .onAppear { start() }
            .onChange(of: cue) { _, _ in start() }
    }
    private func start() {
        guard cue, !shown, !reduce, !skip else { return }
        withAnimation(Motion.arrive) { shown = true }
    }
}

extension View {
    func darsEnterHero() -> some View { modifier(DarsEnterHero()) }
}
