import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class ParentSignUpStore {
    var name = ""
    var phone = ""
    var password = ""
    var code = ""
    private(set) var child: String?
    private(set) var looking = false
    private(set) var working = false
    private(set) var error: String?
    private let client = SupabaseService.client

    struct Lookup: Codable, Sendable {
        let studentId: UUID
        let fullName: String?
        let grade: String?
        let section: String?
        enum CodingKeys: String, CodingKey {
            case grade, section
            case studentId = "student_id"; case fullName = "full_name"
        }
    }
    struct Request: Encodable { let full_name: String; let phone: String; let password: String; let code: String }
    struct Reply: Decodable { let ok: Bool?; let error: String? }

    var digits: String { phone.filter(\.isNumber) }
    var canSubmit: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && digits.count >= 7 && password.count >= 6 && child != nil }

    func lookUp() async {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard c.count >= 4 else { return }
        looking = true
        error = nil
        child = nil
        defer { looking = false }
        do {
            let rows: [Lookup] = try await client.rpc("family_code_lookup", params: ["code": c]).execute().value
            if let found = rows.first {
                child = [found.fullName, [found.grade, found.section].compactMap { $0 }.joined()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                HapticEngine.play(.success)
            } else {
                error = "No student has that code. Ask the school for it."
                HapticEngine.play(.error)
            }
        } catch {
            self.error = "Couldn't reach the school. Check the connection."
        }
    }

    func signUp() async -> Bool {
        guard canSubmit else { return false }
        working = true
        error = nil
        defer { working = false }
        do {
            let reply: Reply = try await client.functions.invoke("parent-signup", options: FunctionInvokeOptions(
                body: Request(full_name: name.trimmingCharacters(in: .whitespaces), phone: digits, password: password,
                              code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())))
            if reply.ok == true { return true }
            error = explain(reply.error)
            HapticEngine.play(.error)
            return false
        } catch {
            self.error = explain(String(describing: error))
            HapticEngine.play(.error)
            return false
        }
    }

    private func explain(_ code: String?) -> String {
        guard let code else { return "Couldn't make the account." }
        if code.contains("phone_taken") || code.contains("already") { return "An account already uses that number. Try signing in instead." }
        if code.contains("invalid_code") || code.contains("unknown_code") { return "That family code is not right." }
        if code.contains("weak_password") { return "Use at least 6 characters." }
        return "Couldn't make the account. Check the connection and try again."
    }
}

struct ParentSignUpView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var store = ParentSignUpStore()
    @State private var scanning = false
    @State private var done = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("You need your child's family code. The school gives it to you, and it is on their profile page in the app.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                codeHalf
                accountHalf
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                DarsButton(title: "Create the account", kind: .primary, systemImage: "arrow.right", isLoading: store.working, fullWidth: true) {
                    Task {
                        if await store.signUp() {
                            await auth.signIn(email: store.digits, password: store.password)
                            done = true
                        }
                    }
                }
                .disabled(!store.canSubmit)
                Spacer(minLength: 60)
            }
            .padding(Metrics.Space.md)
            .animation(Motion.arrive, value: store.child)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("I'm a parent")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            ScanCodeSheet { store.code = $0; Task { await store.lookUp() } }
        }
        .onChange(of: done) { if done { dismiss() } }
    }

    @ViewBuilder
    private var codeHalf: some View {
        SectionLabel("Your child's family code")
        HStack(spacing: 8) {
            TextField("e.g. 4H2K9P", text: Binding(get: { store.code }, set: { store.code = $0.uppercased() }))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(size: 20, weight: .bold, design: .rounded)).kerning(2)
                .submitLabel(.search).onSubmit { Task { await store.lookUp() } }
                .padding(.horizontal, 14).frame(height: 54)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button { HapticEngine.play(.selection); scanning = true } label: {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 19)).frame(width: 54, height: 54)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            DarsButton(title: "Find", kind: .primary, systemImage: "magnifyingglass", isLoading: store.looking) {
                Task { await store.lookUp() }
            }
        }
        if let child = store.child {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success)
                Text(child).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
            }
            .padding(Metrics.Space.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(DarsColor.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var accountHalf: some View {
        SectionLabel("You")
        DarsField(title: "Your name", text: Binding(get: { store.name }, set: { store.name = $0 }))
        DarsField(title: "Your phone", text: Binding(get: { store.phone }, set: { store.phone = $0 }), keyboard: .phonePad)
        SecureField("Choose a password", text: Binding(get: { store.password }, set: { store.password = $0 }))
            .textContentType(.newPassword)
            .padding(.horizontal, 14).frame(height: 50)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        Text("You sign in with that number and that password. There is no email to remember.")
            .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
    }
}

struct JoinView: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var found: String?
    @State private var looking = false
    @State private var working = false
    @State private var joined = false
    @State private var error: String?
    @State private var scanning = false

    private var isParent: Bool { profile.role == .parent }

    struct ClassLookup: Codable, Sendable {
        let classId: UUID
        let name: String?
        let grade: String?
        let section: String?
        let schoolName: String?
        enum CodingKeys: String, CodingKey {
            case name, grade, section
            case classId = "class_id"; case schoolName = "school_name"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text(isParent
                     ? "Type your child's family code to add them to your account."
                     : "Type the code your teacher shows on the class page.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                HStack(spacing: 8) {
                    TextField(isParent ? "Family code" : "Class code", text: Binding(get: { code }, set: { code = $0.uppercased() }))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(size: 22, weight: .bold, design: .rounded)).kerning(2)
                        .submitLabel(.search).onSubmit { Task { await look() } }
                        .padding(.horizontal, 14).frame(height: 56)
                        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button { HapticEngine.play(.selection); scanning = true } label: {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 19)).frame(width: 56, height: 56)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if looking { ProgressView().frame(maxWidth: .infinity) }
                if let found {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success)
                        Text(found).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    }
                    .padding(Metrics.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DarsColor.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                if !isParent && found != nil {
                    Text("Joining moves you into this class. A student is in one class at a time.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                Spacer()
                DarsButton(title: isParent ? "Link this child" : "Join this class", kind: .primary, systemImage: "checkmark", isLoading: working, fullWidth: true) {
                    Task { await commit() }
                }
                .disabled(found == nil)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle(isParent ? "Add a child" : "Join a class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $scanning) { ScanCodeSheet { code = $0; Task { await look() } } }
            .animation(Motion.arrive, value: found)
            .onChange(of: joined) { if joined { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func look() async {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard c.count >= 4 else { return }
        looking = true
        error = nil
        found = nil
        defer { looking = false }
        do {
            if isParent {
                let rows: [ParentSignUpStore.Lookup] = try await SupabaseService.client.rpc("family_code_lookup", params: ["code": c]).execute().value
                if let r = rows.first {
                    found = [r.fullName, [r.grade, r.section].compactMap { $0 }.joined()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                } else { error = "No student has that code." }
            } else {
                let rows: [ClassLookup] = try await SupabaseService.client.rpc("class_code_lookup", params: ["code": c]).execute().value
                if let r = rows.first {
                    found = [(r.grade ?? "") + (r.section ?? ""), r.schoolName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                } else { error = "No class has that code." }
            }
            if found != nil { HapticEngine.play(.success) } else { HapticEngine.play(.error) }
        } catch {
            self.error = "Couldn't reach the school. Check the connection."
        }
    }

    private func commit() async {
        working = true
        error = nil
        defer { working = false }
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            _ = try await SupabaseService.client.rpc(isParent ? "link_child" : "join_class", params: ["code": c]).execute()
            HapticEngine.play(.success)
            joined = true
        } catch {
            let t = String(describing: error)
            if t.contains("unknown_code") { self.error = "That code is not right." }
            else if t.contains("wrong_school") { self.error = "That code belongs to another school." }
            else if t.contains("not_a_student") { self.error = "Only a student can join a class." }
            else { self.error = "Couldn't do it. Try again." }
            HapticEngine.play(.error)
        }
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var working = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ask the office", systemImage: "building.2.fill").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    Text("They set a new password for you on the spot. For a student or a parent this is the way — there is no inbox to send a link to.")
                        .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                }
                .padding(Metrics.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(DarsColor.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                SectionLabel("Or, if you have an email")
                DarsField(title: "Email", text: $email, keyboard: .emailAddress, capitalization: .never)
                if sent {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success)
                        Text("If that address has an account, a link is on its way.").darsType(.footnote).foregroundStyle(DarsColor.labelPrimary)
                    }
                    .padding(Metrics.Space.md).background(DarsColor.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    DarsButton(title: "Send me a link", kind: .secondary, systemImage: "envelope", isLoading: working, fullWidth: true) {
                        Task { await send() }
                    }
                    .disabled(!email.contains("@"))
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer()
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Forgotten password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .animation(Motion.arrive, value: sent)
        }
        .presentationDetents([.medium])
    }

    private func send() async {
        working = true
        defer { working = false }
        do {
            try await SupabaseService.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces))
            sent = true
            HapticEngine.play(.success)
        } catch {
            sent = true
        }
    }
}
