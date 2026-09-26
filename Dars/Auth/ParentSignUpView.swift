import Foundation
import Observation
import SwiftUI
import Supabase

enum ParentRole { case father, mother }

enum FamilyStatus: String, CaseIterable, Identifiable {
    case married, divorced, separated
    case fatherDeceased = "father_deceased"
    case motherDeceased = "mother_deceased"
    case bothDeceased = "both_deceased"
    case other
    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .married: return "parent_status_married"
        case .divorced: return "parent_status_divorced"
        case .separated: return "parent_status_separated"
        case .fatherDeceased: return "parent_status_father_deceased"
        case .motherDeceased: return "parent_status_mother_deceased"
        case .bothDeceased: return "parent_status_both_deceased"
        case .other: return "parent_status_other"
        }
    }
}

@MainActor
@Observable
final class ParentSignUpStore {
    var step = 1
    private(set) var code = ""
    private(set) var checking = false
    private(set) var codeFound = false
    private(set) var childName: String?
    private(set) var childClass: String?

    var role: ParentRole = .father
    var fatherName = ""
    var fatherPhone = ""
    var motherName = ""
    var motherPhone = ""
    var status: FamilyStatus = .married
    var password = ""

    private(set) var working = false
    var error: String?
    var serverError: String?

    struct Lookup: Decodable, Sendable {
        let studentId: String?
        let fullName: String?
        let grade: String?
        let section: String?
        enum CodingKeys: String, CodingKey {
            case grade, section
            case studentId = "student_id"
            case fullName = "full_name"
        }
    }
    private struct SignUp: Encodable, Sendable {
        let phone: String
        let password: String
        let name: String
        let father_name: String
        let father_phone: String
        let mother_name: String
        let mother_phone: String
        let family_status: String
        let code: String
    }
    private struct Reply: Decodable { let error: String? }

    func onCode(_ raw: String) {
        code = String(raw.filter { !$0.isWhitespace && $0 != "-" }.uppercased().prefix(6))
        error = nil
        serverError = nil
        childName = nil
    }

    func back() {
        if step == 2 {
            withAnimation(Motion.emphasis) {
                step = 1
                error = nil
                serverError = nil
            }
        }
    }

    func checkCode() async {
        guard code.count >= 4, !checking else { return }
        checking = true
        error = nil
        serverError = nil
        let rows: [Lookup] = (try? await SupabaseService.client.rpc("family_code_lookup", params: ["code": code]).execute().value) ?? []
        guard let found = rows.first, let name = found.fullName else {
            checking = false
            error = L("join_error_not_found")
            return
        }
        checking = false
        codeFound = true
        try? await Task.sleep(for: .milliseconds(620))
        codeFound = false
        childName = name
        let label = [found.grade, found.section].compactMap { $0 }.joined()
        childClass = label.isEmpty ? nil : label
        withAnimation(Motion.emphasis) { step = 2 }
    }

    func create() async {
        guard !working else { return }
        let loginPhone = role == .father ? fatherPhone : motherPhone
        let name = (role == .father ? fatherName : motherName).trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            error = L(role == .father ? "parent_need_father_name" : "parent_need_mother_name")
            serverError = nil
            return
        }
        if loginPhone.filter(\.isNumber).count < 6 {
            error = L(role == .father ? "parent_need_father_phone" : "parent_need_mother_phone")
            serverError = nil
            return
        }
        if password.count < 6 {
            error = L("parent_password_short")
            serverError = nil
            return
        }
        working = true
        error = nil
        serverError = nil
        do {
            let body = SignUp(
                phone: loginPhone,
                password: password,
                name: name,
                father_name: fatherName.trimmingCharacters(in: .whitespaces),
                father_phone: fatherPhone.trimmingCharacters(in: .whitespaces),
                mother_name: motherName.trimmingCharacters(in: .whitespaces),
                mother_phone: motherPhone.trimmingCharacters(in: .whitespaces),
                family_status: status.rawValue,
                code: code.trimmingCharacters(in: .whitespaces)
            )
            let reply: Reply = try await SupabaseService.client.functions.invoke("parent-signup", options: FunctionInvokeOptions(body: body))
            if let problem = reply.error {
                let known: String?
                switch problem {
                case "phone_taken": known = "parent_phone_taken"
                case "invalid_code": known = "parent_code_expired"
                case "weak_password": known = "parent_password_short"
                case "bad_phone": known = "parent_need_father_phone"
                default: known = nil
                }
                working = false
                error = known.map { L($0) }
                serverError = known == nil ? problem : nil
                return
            }
            let digits = loginPhone.filter(\.isNumber)
            _ = try await SupabaseService.auth.signIn(email: "p\(digits)@parent.kurdedu.app", password: password)
            working = false
        } catch {
            working = false
            self.error = L("error_network")
        }
    }
}

struct ParentSignUpView: View {
    var initialCode: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var store = ParentSignUpStore()
    @State private var revealed = false
    @State private var burst = false
    @State private var burstPlayed = false
    @State private var scanning = false

    private var steps: [String] { [L("parent_step_code"), L("parent_step_child"), L("parent_step_details")] }

    var body: some View {
        ZStack {
            AuthShell(title: L("parent_join_title"), subtitle: L("parent_join_sub"), onBack: { store.step == 2 ? store.back() : dismiss() }) {
                ZStack {
                    if store.step == 1 {
                        codeStep.transition(.asymmetric(insertion: .opacity.animation(Motion.emphasis), removal: .opacity.animation(Motion.standard)))
                    } else {
                        detailsStep.transition(.asymmetric(insertion: .opacity.animation(Motion.emphasis), removal: .opacity.animation(Motion.standard)))
                    }
                }
            }
            if burst {
                LinkBurst(
                    title: L("parent_linked"),
                    subtitle: [store.childName, store.childClass].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
                ) { burst = false }
                .transition(.opacity)
            }
        }
        .onAppear {
            if let initialCode, store.code.isEmpty { store.onCode(JoinLink.code(from: initialCode)) }
        }
        .onChange(of: store.step) { _, now in
            if now == 2 && !burstPlayed {
                burstPlayed = true
                burst = true
            }
        }
        .sheet(isPresented: $scanning) {
            ScanCodeSheet { code in store.onCode(JoinLink.code(from: code)) }
        }
    }

    private var codeStep: some View {
        VStack(spacing: 0) {
            AuthCard {
                StepsLine(current: 0, labels: steps)
                PanelHeading(title: L("parent_code_label"), subtitle: L("parent_code_help"))
                AuthLabel(text: L("parent_code_label"))
                CodeBoxes(
                    value: Binding(get: { store.code }, set: { store.onCode($0) }),
                    state: store.codeFound ? .success : (store.checking ? .checking : ((store.error != nil || store.serverError != nil) ? .error : .idle)),
                    description: L("parent_code_label"),
                    onFilled: { _ in hideKeyboard(); Task { await store.checkCode() } }
                )
                .padding(.vertical, 6)
                Text(verbatim: L("family_code_where_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textMuted)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                Reassure(icon: "Filled.VerifiedUser", text: L("parent_code_reassure"))
                MessageLine(message: store.error ?? store.serverError)
                    .padding(.bottom, (store.error ?? store.serverError) == nil ? 0 : 8)
                Spacer().frame(height: 8)
                ActionButton(title: L("parent_find_child"), enabled: store.code.count == 6, working: store.checking) {
                    hideKeyboard()
                    Task { await store.checkCode() }
                }
            }
            MotionButton(title: LocalizedStringKey(L("join_scan_instead"))) { scanning = true }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepsLine(current: 2, labels: steps)
                .darsStagger(0, step: 0.06, delay: 0.04, rise: 10)
            HStack(spacing: 10) {
                MaterialIcon("Filled.CheckCircle", size: 20).foregroundStyle(Tokens.success)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: store.childName ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.text)
                    if let c = store.childClass {
                        Text(verbatim: c).font(.system(size: 12.5)).foregroundStyle(Tokens.textSub)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Tokens.success.opacity(0.12), in: RR(16))
            .darsStagger(0, step: 0.06, delay: 0.04, rise: 10)

            Spacer().frame(height: 12)

            AuthCard {
                AuthLabel(text: L("parent_which_are_you"))
                HStack(spacing: 8) {
                    ChoiceCard(title: L("parent_father"), icon: "Filled.Person", selected: store.role == .father, subtitle: L("parent_role_hint")) {
                        store.role = .father
                        store.error = nil
                    }
                    ChoiceCard(title: L("parent_mother"), icon: "Filled.Person", selected: store.role == .mother, subtitle: L("parent_role_hint")) {
                        store.role = .mother
                        store.error = nil
                    }
                }
                .padding(.top, 4)
                Text(verbatim: L("parent_login_number"))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textMuted)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                AuthLabel(text: L("admin_father_name"))
                AuthField(text: $store.fatherName, icon: "Filled.Person", placeholder: L("parent_father_name_hint"), content: .name, capitalization: .words)
                AuthLabel(text: L("admin_father_phone") + (store.role == .father ? L("parent_login_suffix") : ""))
                AuthField(text: $store.fatherPhone, icon: "Filled.Phone", placeholder: L("parent_phone_hint"), keyboard: .phonePad, content: .telephoneNumber)

                AuthLabel(text: L("admin_mother_name")).padding(.top, 8)
                AuthField(text: $store.motherName, icon: "Filled.Person", placeholder: L("parent_mother_name_hint"), content: .name, capitalization: .words)
                AuthLabel(text: L("admin_mother_phone") + (store.role == .mother ? L("parent_login_suffix") : ""))
                AuthField(text: $store.motherPhone, icon: "Filled.Phone", placeholder: L("parent_phone_hint"), keyboard: .phonePad, content: .telephoneNumber)

                AuthLabel(text: L("parent_family_status")).padding(.top, 8)
                FlowLayout(spacing: 8) {
                    ForEach(FamilyStatus.allCases) { option in
                        MotionChip(text: L(option.labelKey), selected: store.status == option) {
                            store.status = option
                            store.error = nil
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 16)

                AuthLabel(text: L("parent_password_label"))
                AuthField(
                    text: $store.password,
                    icon: "Filled.Lock",
                    placeholder: L("parent_password_help"),
                    secure: true,
                    revealed: revealed,
                    content: .newPassword,
                    submit: .done,
                    onSubmit: { hideKeyboard(); Task { await store.create() } },
                    onReveal: { HapticEngine.play(.selection); revealed.toggle() }
                )
                MessageLine(message: store.error ?? store.serverError)
                    .padding(.top, (store.error ?? store.serverError) == nil ? 0 : 8)
                Spacer().frame(height: 16)
                ActionButton(title: L("parent_create_account"), enabled: true, working: store.working) {
                    hideKeyboard()
                    Task { await store.create() }
                }
            }
            .darsStagger(1, step: 0.06, delay: 0.04, rise: 10)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

struct LinkBurst: View {
    let title: String
    let subtitle: String?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var veil: CGFloat = 0
    @State private var meet: CGFloat = 0
    @State private var mark: CGFloat = 0
    @State private var ring1: CGFloat = 0
    @State private var ring2: CGFloat = 0
    @State private var reach: CGFloat = 0
    @State private var words: CGFloat = 0
    @State private var finished = false

    private let reachIcons: [(String, Double)] = [
        ("Filled.WorkspacePremium", -90), ("Filled.CalendarMonth", 0), ("Filled.DoneAll", 90), ("Filled.Forum", 180),
    ]

    var body: some View {
        GeometryReader { g in
            let start = min(g.size.width * 0.42, 190)
            VStack(spacing: 44) {
                ZStack {
                    MeetLines(progress: meet, start: start)
                        .frame(width: 200, height: 200)
                    BurstRing(progress: ring1)
                    BurstRing(progress: ring2)
                    ForEach(reachIcons, id: \.0) { icon, angle in
                        ReachDot(progress: reach, angle: angle, icon: icon)
                    }
                    BurstNode(progress: meet, direction: -1, start: start, icon: "Filled.Person")
                    BurstNode(progress: meet, direction: 1, start: start, icon: "Filled.People")
                    MaterialIcon("Filled.Check", size: 40)
                        .foregroundStyle(Tokens.onAccent)
                        .frame(width: 78, height: 78)
                        .background(Tokens.accent, in: Circle())
                        .scaleEffect(0.35 + 0.65 * mark)
                        .opacity(mark)
                }
                .frame(width: 200, height: 200)
                VStack(spacing: 6) {
                    Text(verbatim: title)
                        .font(.system(size: 22, weight: .bold))
                        .darsTracking(-0.4)
                        .foregroundStyle(Tokens.text)
                        .multilineTextAlignment(.center)
                    if let subtitle {
                        Text(verbatim: subtitle).font(.system(size: 15)).foregroundStyle(Tokens.textMuted).multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .opacity(words)
                .offset(y: (1 - words) * 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tokens.bg.ignoresSafeArea())
        .opacity(veil)
        .contentShape(Rectangle())
        .onTapGesture { done() }
        .task { await play() }
    }

    private func done() {
        guard !finished else { return }
        finished = true
        onDone()
    }

    private func play() async {
        if reduce {
            veil = 1; meet = 1; mark = 1; reach = 1; words = 1
            HapticEngine.play(.success)
            try? await Task.sleep(for: .milliseconds(1400))
            done()
            return
        }
        withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.1)) { veil = 1 }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(Motion.spring(damping: 0.69, stiffness: 42)) { meet = 1 }
        try? await Task.sleep(for: .milliseconds(520))
        HapticEngine.play(.success)
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(Motion.spring(damping: 0.74, stiffness: 220)) { mark = 1 }
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.95)) { ring1 = 1 }
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.95).delay(0.15)) { ring2 = 1 }
        withAnimation(Motion.spring(damping: 0.65, stiffness: 60).delay(0.22)) { reach = 1 }
        withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.2).delay(0.32)) { words = 1 }
        try? await Task.sleep(for: .milliseconds(2700))
        done()
    }
}

private struct MeetLines: View, Animatable {
    var progress: CGFloat
    let start: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        Canvas { ctx, size in
            let p = progress
            guard p > 0, p < 0.86 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let gap = (1 - p) * start
            let alpha = min(max(p * 1.6, 0), 0.9)
            let reachIn = gap * p
            var a = Path()
            a.move(to: CGPoint(x: c.x - gap, y: c.y))
            a.addLine(to: CGPoint(x: c.x - gap + reachIn, y: c.y))
            var b = Path()
            b.move(to: CGPoint(x: c.x + gap, y: c.y))
            b.addLine(to: CGPoint(x: c.x + gap - reachIn, y: c.y))
            let style = StrokeStyle(lineWidth: 2, lineCap: .round)
            ctx.stroke(a, with: .color(Tokens.accent.opacity(alpha)), style: style)
            ctx.stroke(b, with: .color(Tokens.accent.opacity(alpha)), style: style)
        }
        .allowsHitTesting(false)
    }
}

private struct BurstRing: View, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let p = progress
        let alpha: CGFloat = p <= 0 ? 0 : (p < 0.15 ? p / 0.15 * 0.5 : 0.5 * (1 - (p - 0.15) / 0.85))
        Circle()
            .strokeBorder(Tokens.accent, lineWidth: 2)
            .frame(width: 96, height: 96)
            .scaleEffect(0.5 + 2.6 * p)
            .opacity(alpha)
    }
}

private struct ReachDot: View, Animatable {
    var progress: CGFloat
    let angle: Double
    let icon: String
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let p = progress
        let rad = angle * .pi / 180
        let s: CGFloat = p < 0.6 ? 0.3 + (1.06 - 0.3) * (p / 0.6) : 1.06 - 0.06 * ((p - 0.6) / 0.4)
        MaterialIcon(icon, size: 15)
            .foregroundStyle(Tokens.accentText)
            .frame(width: 32, height: 32)
            .background(Tokens.accent.opacity(0.13), in: Circle())
            .scaleEffect(s)
            .opacity(min(max(p / 0.4, 0), 1))
            .offset(x: cos(rad) * 78 * p, y: sin(rad) * 78 * p)
    }
}

private struct BurstNode: View, Animatable {
    var progress: CGFloat
    let direction: CGFloat
    let start: CGFloat
    let icon: String
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let p = progress
        MaterialIcon(icon, size: 22)
            .foregroundStyle(Tokens.accentText)
            .frame(width: 52, height: 52)
            .background(Tokens.card, in: Circle())
            .overlay(Circle().strokeBorder(Tokens.border, lineWidth: 0.5))
            .scaleEffect(0.7 + 0.3 * p)
            .opacity(p < 0.86 ? 1 : 1 - (p - 0.86) / 0.14)
            .offset(x: direction * start * (1 - p))
    }
}
