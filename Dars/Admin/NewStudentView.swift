import Foundation
import SwiftUI
import Supabase

struct NewStudentView: View {
    let me: Profile
    @State private var name = ""
    @State private var nameKu = ""
    @State private var classId: UUID?
    @State private var classes: [AdminClassesStore.Line] = []
    @State private var password = ResetPasswordSheet.suggestion()
    @State private var working = false
    @State private var created: (name: String, code: String)?
    @State private var error: String?

    struct Request: Encodable { let code: String; let full_name: String; let email: String; let password: String }
    struct Reply: Decodable { let ok: Bool?; let `class`: String?; let error: String? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if let created {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(created.name) is enrolled", systemImage: "checkmark.circle.fill").foregroundStyle(DarsColor.success).darsType(.headline)
                        Text("They sign in with *I'm a student*, this class code, their own name, and this password.")
                            .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Class code").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                Spacer()
                                Text(created.code).font(.system(size: 18, weight: .bold, design: .rounded)).kerning(2).foregroundStyle(DarsColor.accentLabel)
                            }
                            Divider()
                            HStack {
                                Text("Password").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                Spacer()
                                Text(password).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(DarsColor.labelPrimary)
                            }
                        }
                        .padding(Metrics.Space.md).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        HStack(spacing: 14) {
                            Button {
                                UIPasteboard.general.string = "Class code: \(created.code)\nPassword: \(password)"
                                HapticEngine.play(.success)
                            } label: { Label("Copy both", systemImage: "doc.on.doc").font(.system(size: 14, weight: .semibold)) }
                            Spacer()
                            Button("Add another") { reset() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
                        }
                    }
                    .padding(Metrics.Space.md).background(DarsColor.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    SectionLabel("Who they are")
                    DarsField(title: "Full name", text: $name)
                    DarsField(title: "Name in Kurdish", text: $nameKu)

                    SectionLabel("Class")
                    if classes.isEmpty {
                        EmptyCard("Make a class first; a student joins one.")
                    } else {
                        CardList {
                            ForEach(Array(classes.enumerated()), id: \.element.id) { i, line in
                                if i > 0 { RowDivider(inset: Metrics.Space.md) }
                                Button {
                                    HapticEngine.play(.selection)
                                    classId = line.id
                                } label: {
                                    HStack {
                                        Text(line.klass.label).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                        Text("\(line.students) students").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                        Spacer()
                                        if line.joinCode == nil {
                                            Text("No code").darsType(.caption).foregroundStyle(DarsColor.warning)
                                        } else if classId == line.id {
                                            Image(systemName: "checkmark").foregroundStyle(DarsColor.accentLabel)
                                        }
                                    }
                                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(line.joinCode == nil)
                            }
                        }
                    }

                    SectionLabel("Password")
                    HStack(spacing: 8) {
                        DarsField(title: "Password", text: $password, capitalization: .never)
                        Button { password = ResetPasswordSheet.suggestion(); HapticEngine.play(.selection) } label: {
                            Image(systemName: "die.face.5").font(.system(size: 17)).frame(width: 50, height: 50)
                                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Say it to them in person and ask them to change it in Profile. You can set a new one any time from their page.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)

                    DarsButton(title: "Enrol the student", kind: .primary, systemImage: "person.badge.plus", isLoading: working, fullWidth: true) {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || chosenCode == nil || password.count < 6)
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
            .animation(Motion.arrive, value: created?.code)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Add a student")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let store = AdminClassesStore()
            await store.load()
            classes = store.lines
            classId = classes.first { $0.joinCode != nil }?.id
        }
    }

    private var chosenCode: String? { classes.first { $0.id == classId }?.joinCode }

    private func handle(for name: String) -> String {
        let ascii = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "." }
        var slug = String(ascii).split(separator: ".").joined(separator: ".")
        if slug.isEmpty { slug = "student" }
        return "\(slug.prefix(24)).\(Int.random(in: 1000...9999))@student.kurdedu.app"
    }

    private func reset() {
        created = nil; name = ""; nameKu = ""; error = nil
        password = ResetPasswordSheet.suggestion()
    }

    private func create() async {
        guard let code = chosenCode else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        working = true
        error = nil
        defer { working = false }
        do {
            let reply: Reply = try await SupabaseService.client.functions.invoke(
                "student-signup",
                options: FunctionInvokeOptions(body: Request(code: code, full_name: trimmed, email: handle(for: trimmed), password: password))
            )
            if reply.ok == true {
                if !nameKu.trimmingCharacters(in: .whitespaces).isEmpty {
                    struct Patch: Encodable { let full_name_ku: String }
                    _ = try? await SupabaseService.client.from("profiles")
                        .update(Patch(full_name_ku: nameKu.trimmingCharacters(in: .whitespaces)))
                        .eq("full_name", value: trimmed).eq("school_id", value: me.schoolId?.uuidString ?? "").execute()
                }
                created = (trimmed, code)
                HapticEngine.play(.success)
            } else {
                error = explain(reply.error)
                HapticEngine.play(.error)
            }
        } catch {
            self.error = explain(String(describing: error))
            HapticEngine.play(.error)
        }
    }

    private func explain(_ code: String?) -> String {
        guard let code else { return "Couldn't enrol them." }
        if code.contains("email_taken") { return "An account already exists with that name's handle. Try again — a new number is drawn each time." }
        if code.contains("invalid_code") { return "That class has no join code yet." }
        if code.contains("weak_password") { return "Use at least 6 characters." }
        return "Couldn't enrol them. Check the connection and try again."
    }
}
