import Foundation
import Observation
import SwiftUI
import Supabase

struct RosterEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let fullName: String?
    let fullNameKu: String?
    let avatarInitials: String?
    let avatarColor: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case fullNameKu = "full_name_ku"
        case avatarInitials = "avatar_initials"
        case avatarColor = "avatar_color"
        case avatarUrl = "avatar_url"
    }

    func displayName(kurdish: Bool) -> String {
        if kurdish, let ku = fullNameKu, !ku.isEmpty { return ku }
        return fullName ?? ""
    }

    var initials: String { avatarInitials ?? String((fullName ?? "").prefix(1)).uppercased() }
}

@MainActor
@Observable
final class StudentDoorStore {
    enum Step { case code, name }

    var step: Step = .code
    var code = ""
    private(set) var roster: [RosterEntry] = []
    var chosen: RosterEntry?
    var password = ""
    private(set) var working = false
    private(set) var codeFound = false
    var error: String?

    static let unknownCode = "unknown_code"
    static let badCredentials = "bad_credentials"

    func onCode(_ raw: String) {
        code = String(raw.filter { !$0.isWhitespace && $0 != "-" }.uppercased().prefix(6))
        error = nil
    }

    func loadRoster() async {
        guard code.count >= 4, !working else { return }
        working = true
        error = nil
        do {
            let rows: [RosterEntry] = try await SupabaseService.client
                .rpc("class_roster", params: ["p_code": code])
                .execute()
                .value
            if rows.isEmpty {
                working = false
                error = Self.unknownCode
                return
            }
            working = false
            codeFound = true
            try? await Task.sleep(for: .milliseconds(620))
            codeFound = false
            roster = rows.sorted { ($0.fullName ?? "") < ($1.fullName ?? "") }
            withAnimation(Motion.emphasis) { step = .name }
        } catch {
            working = false
            self.error = String(describing: error)
        }
    }

    func back() {
        if step == .name {
            withAnimation(Motion.emphasis) {
                step = .code
                roster = []
                chosen = nil
                password = ""
                error = nil
            }
        }
    }

    func signIn() async {
        guard let who = chosen, !password.isEmpty, !working else { return }
        working = true
        error = nil
        struct Body: Encodable, Sendable { let student_id: String; let password: String }
        struct Reply: Decodable {
            struct Session: Decodable { let access_token: String; let refresh_token: String? }
            let session: Session?
            let error: String?
        }
        do {
            let reply: Reply = try await SupabaseService.client.functions
                .invoke("student-login", options: FunctionInvokeOptions(body: Body(student_id: who.id.uuidString, password: password)))
            if let s = reply.session {
                try await SupabaseService.auth.setSession(accessToken: s.access_token, refreshToken: s.refresh_token ?? "")
                HapticEngine.play(.success)
            } else {
                error = reply.error ?? Self.badCredentials
            }
        } catch {
            self.error = Self.badCredentials
        }
        working = false
    }
}

struct StudentSignInView: View {
    var initialCode: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var store = StudentDoorStore()
    @State private var revealed = false

    private var steps: [String] { [L("student_signin_step_code"), L("student_signin_step_name"), L("login_password")] }

    var body: some View {
        AuthShell(title: L("login_sign_in"), subtitle: subtitle, onBack: back) {
            ZStack {
                if store.step == .code {
                    codeStep.transition(.asymmetric(insertion: .opacity.animation(Motion.emphasis), removal: .opacity.animation(Motion.standard)))
                } else {
                    nameStep.transition(.asymmetric(insertion: .opacity.animation(Motion.emphasis), removal: .opacity.animation(Motion.standard)))
                }
            }
        }
        .onAppear {
            if let initialCode, store.code.isEmpty {
                store.onCode(initialCode)
            }
        }
    }

    private var subtitle: String {
        switch store.step {
        case .code: return L("student_signin_code_body")
        case .name: return P("classes_student_count", store.roster.count)
        }
    }

    private func back() {
        if store.step == .name { store.back() } else { dismiss() }
    }

    private var codeStep: some View {
        AuthCard {
            StepsLine(current: 0, labels: steps)
            PanelHeading(title: L("student_signin_code_title"), subtitle: L("student_signin_code_hint"))
            AuthLabel(text: L("student_signin_class_code"))
            CodeBoxes(
                value: Binding(get: { store.code }, set: { store.onCode($0) }),
                state: store.codeFound ? .success : (store.working ? .checking : (store.error != nil ? .error : .idle)),
                description: L("student_signin_class_code"),
                onFilled: { _ in hideKeyboard(); Task { await store.loadRoster() } }
            )
            .padding(.vertical, 6)
            Text(verbatim: L("code_where_hint"))
                .font(.system(size: 12))
                .foregroundStyle(Tokens.textMuted)
                .padding(.top, 2)
                .padding(.bottom, 4)
            Reassure(icon: "Filled.VerifiedUser", text: L("student_signin_reassure"))
            MessageLine(message: store.error.map { $0 == StudentDoorStore.unknownCode ? L("student_signin_wrong_code") : L("student_signin_could_not_check") })
                .padding(.bottom, store.error == nil ? 0 : 8)
            Spacer().frame(height: 8)
            ActionButton(title: L("join_continue"), enabled: store.code.count == 6, working: store.working) {
                hideKeyboard()
                Task { await store.loadRoster() }
            }
        }
    }

    private var nameStep: some View {
        AuthCard {
            StepsLine(current: store.chosen == nil ? 1 : 2, labels: steps)
            PanelHeading(title: L("student_signin_pick_name"), subtitle: L("student_signin_pick_name_body"))
            if store.roster.isEmpty {
                Reassure(icon: "Filled.Groups", text: L("student_signin_no_one"))
            }
            VStack(spacing: 8) {
                ForEach(Array(store.roster.enumerated()), id: \.element.id) { index, student in
                    NameRow(
                        name: student.displayName(kurdish: language.language.isKurdish),
                        initials: student.initials,
                        colour: Color(hexString: student.avatarColor),
                        avatarURL: student.avatarUrl,
                        selected: store.chosen?.id == student.id
                    ) {
                        withAnimation(Motion.emphasis) {
                            store.chosen = student
                            store.error = nil
                        }
                    }
                    .darsStagger(index, step: 0.04, delay: 0.06, rise: 8)
                }
            }
            if store.chosen != nil {
                VStack(alignment: .leading, spacing: 0) {
                    AuthLabel(text: L("login_password"))
                    AuthField(
                        text: Binding(get: { store.password }, set: { store.password = $0; store.error = nil }),
                        icon: "Filled.Lock",
                        placeholder: L("student_signin_password_placeholder"),
                        secure: true,
                        revealed: revealed,
                        content: .password,
                        submit: .go,
                        onSubmit: { hideKeyboard(); Task { await store.signIn() } },
                        onReveal: { HapticEngine.play(.selection); revealed.toggle() }
                    )
                    Reassure(icon: "Filled.Lock", text: L("student_signin_password_reassure"))
                }
                .padding(.top, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            MessageLine(message: store.error.map { $0 == "not_a_student" ? L("student_signin_not_a_student") : L("student_signin_wrong_password") })
                .padding(.top, store.error == nil ? 0 : 8)
            Spacer().frame(height: 16)
            ActionButton(title: L("login_sign_in"), enabled: store.chosen != nil && !store.password.isEmpty, working: store.working) {
                hideKeyboard()
                Task { await store.signIn() }
            }
            if store.chosen == nil {
                Text(verbatim: L("student_signin_pick_first"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.textMuted)
                    .padding(.top, 8)
            }
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
