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
}

@MainActor
@Observable
final class StudentDoorStore {
    var code = ""
    private(set) var roster: [RosterEntry] = []
    private(set) var looking = false
    private(set) var signing = false
    private(set) var error: String?
    var chosen: RosterEntry?
    var password = ""

    func lookUp() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 4 else { return }
        looking = true
        error = nil
        defer { looking = false }
        do {
            let rows: [RosterEntry] = try await SupabaseService.client
                .rpc("class_roster", params: ["p_code": trimmed])
                .execute()
                .value
            roster = rows
            if rows.isEmpty { error = "No class has that code. Ask your teacher for the code on the class page." }
        } catch {
            self.error = "Couldn't reach the school. Check the connection and try again."
        }
    }

    func signIn() async {
        guard let who = chosen, !password.isEmpty else { return }
        signing = true
        error = nil
        defer { signing = false }
        struct Body: Encodable { let student_id: String; let password: String }
        struct Reply: Decodable {
            struct S: Decodable { let access_token: String; let refresh_token: String }
            let session: S?
            let error: String?
        }
        do {
            let reply: Reply = try await SupabaseService.client.functions
                .invoke("student-login", options: FunctionInvokeOptions(body: Body(student_id: who.id.uuidString, password: password)))
            if let s = reply.session {
                try await SupabaseService.auth.setSession(accessToken: s.access_token, refreshToken: s.refresh_token)
                HapticEngine.play(.success)
            } else {
                error = reply.error == "bad_credentials" ? "That password isn't right." : (reply.error ?? "Sign-in failed.")
                HapticEngine.play(.error)
            }
        } catch {
            self.error = String(describing: error).lowercased().contains("401") ? "That password isn't right." : "Couldn't sign in. Check the connection and try again."
            HapticEngine.play(.error)
        }
    }
}

struct StudentSignInView: View {
    @Environment(LanguageStore.self) private var language
    @State private var store = StudentDoorStore()
    @State private var scanning = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your class code").darsType(.title2).foregroundStyle(DarsColor.labelPrimary)
                    Text("The code your teacher shows on the class page. Then tap your own name.")
                        .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                }
                HStack(spacing: Metrics.Space.sm) {
                    TextField("e.g. DEMO10", text: $store.code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .kerning(2)
                        .focused($codeFocused)
                        .submitLabel(.search)
                        .onSubmit { Task { await store.lookUp() } }
                        .padding(.horizontal, 14)
                        .frame(height: 56)
                        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(codeFocused ? DarsColor.accent : DarsColor.separator, lineWidth: codeFocused ? 1.5 : 0.5))
                    Button { HapticEngine.play(.selection); scanning = true } label: {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 19)).frame(width: 56, height: 56)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    DarsButton(title: "Find", kind: .primary, systemImage: "magnifyingglass", isLoading: store.looking) {
                        Task { await store.lookUp() }
                    }
                }

                if !store.roster.isEmpty {
                    Text("Tap your name").darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(store.roster) { who in
                            let on = store.chosen?.id == who.id
                            Button {
                                HapticEngine.play(.selection)
                                withAnimation(Motion.selection) { store.chosen = who }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color(hexString: who.avatarColor)).frame(width: 36, height: 36)
                                        Text(who.avatarInitials ?? String((who.fullName ?? "?").prefix(1))).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                    }
                                    Text(language.language.isKurdish ? (who.fullNameKu ?? who.fullName ?? "") : (who.fullName ?? ""))
                                        .darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity)
                                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? DarsColor.accent : DarsColor.separator, lineWidth: on ? 1.5 : 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let who = store.chosen {
                    VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                        Text("Password for \(who.fullName ?? "")").darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                        SecureField("Password", text: $store.password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { Task { await store.signIn() } }
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DarsColor.separator, lineWidth: 0.5))
                        DarsButton(title: "Sign In", kind: .primary, systemImage: "arrow.right", isLoading: store.signing, fullWidth: true) {
                            Task { await store.signIn() }
                        }
                        .disabled(store.password.isEmpty)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let error = store.error {
                    Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger)
                }
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("I'm a student")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { codeFocused = true }
        .sheet(isPresented: $scanning) {
            ScanCodeSheet { store.code = $0; Task { await store.lookUp() } }
        }
    }
}
