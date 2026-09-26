import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class AdminPeopleStore {
    private(set) var people: [Profile] = []
    private(set) var classOf: [UUID: ClassRow] = [:]
    private(set) var todayStatus: [UUID: AttendanceStatus] = [:]
    private(set) var childrenOf: [UUID: [UUID]] = [:]
    private(set) var classes: [ClassRow] = []
    private(set) var loading = true
    private(set) var error: String?
    var tab = "students"
    var query = ""
    var classFilter: UUID?
    private let client = SupabaseService.client

    struct MemberWithClass: Codable { let class_id: UUID?; let user_id: UUID?; let classes: ClassRow? }
    struct LinkRow2: Codable { let parent_id: UUID; let student_id: UUID }

    func load() async {
        do {
            async let all: [Profile] = try await client.from("profiles").select(Profile.columns).order("full_name").execute().value
            async let members: [MemberWithClass] = (try? await client.from("class_members").select("class_id, user_id, classes(id, name, grade, section, school_id)").execute().value) ?? []
            async let register: [AttendanceRow] = (try? await client.from("attendance").select(AttendanceRow.columns).eq("date", value: DayKey.string(Date())).execute().value) ?? []
            async let links: [LinkRow2] = (try? await client.from("parent_children").select("parent_id, student_id").execute().value) ?? []

            people = try await all
            classOf = Dictionary(try await members.compactMap { m -> (UUID, ClassRow)? in
                guard let u = m.user_id, let c = m.classes else { return nil }
                return (u, c)
            }, uniquingKeysWith: { a, _ in a })
            todayStatus = Dictionary(try await register.map { ($0.studentId, AttendanceStatus(rawValue: $0.status) ?? .present) }, uniquingKeysWith: { a, _ in a })
            childrenOf = Dictionary(grouping: try await links, by: { $0.parent_id }).mapValues { $0.map { $0.student_id } }
            classes = try await DarsData.allClasses()
        } catch { self.error = String(describing: error) }
        loading = false
    }

    var shown: [Profile] {
        let role: Role = tab == "teachers" ? .teacher : (tab == "parents" ? .parent : .student)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return people.filter { p in
            guard p.role == role || (tab == "teachers" && p.role == .admin) else { return false }
            if let f = classFilter, tab == "students", classOf[p.id]?.id != f { return false }
            if q.isEmpty { return true }
            return p.fullName.lowercased().contains(q) || (p.fullNameKu ?? "").contains(q)
        }
    }

    func detail(_ p: Profile) -> String? {
        switch p.role {
        case .student:
            let cls = classOf[p.id]?.label ?? p.classLabel
            let status = todayStatus[p.id].map { " · " + $0.label }
            return (cls ?? "No class") + (status ?? "")
        case .parent:
            let kids = childrenOf[p.id]?.count ?? 0
            return kids == 0 ? "No child linked" : "\(kids) child\(kids == 1 ? "" : "ren")"
        case .teacher: return p.subject
        case .admin: return "Office"
        }
    }
}

struct AdminPeopleView: View {
    let me: Profile
    var tab: String = "students"
    @State private var store = AdminPeopleStore()
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Picker("", selection: Binding(get: { store.tab }, set: { store.tab = $0; store.classFilter = nil })) {
                    Text("Students").tag("students"); Text("Parents").tag("parents"); Text("Teachers").tag("teachers")
                }
                .pickerStyle(.segmented)
                SearchField(text: Binding(get: { store.query }, set: { store.query = $0 }), prompt: "Search by name")
                if store.tab == "students" && store.classes.count > 1 {
                    ChipRow(items: [(nil as UUID?, "All")] + store.classes.map { ($0.id as UUID?, $0.label) },
                            selected: Binding(get: { store.classFilter }, set: { store.classFilter = $0 }))
                }
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.shown.isEmpty {
                    EmptyCard("Nobody here.")
                } else {
                    SectionLabel("People", trailing: "\(store.shown.count)")
                    CardList {
                        ForEach(Array(store.shown.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { RowDivider() }
                            NavigationLink(value: AdminRoute.person(p)) {
                                PersonLine(p, detail: store.detail(p)) {
                                    if p.isSuspended {
                                        Text("Paused").font(.system(size: 11, weight: .bold)).foregroundStyle(DarsColor.danger)
                                            .padding(.horizontal, 7).padding(.vertical, 3).background(DarsColor.danger.opacity(0.15), in: Capsule())
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !started { started = true; store.tab = tab }
            await store.load()
        }
        .refreshable { await store.load() }
    }
}

@MainActor
@Observable
final class AdminPersonStore {
    private(set) var contact: Contact?
    private(set) var parents: [Profile] = []
    private(set) var children: [Profile] = []
    private(set) var klass: ClassRow?
    private(set) var classes: [ClassRow] = []
    private(set) var taught: [TeacherAssignmentRow] = []
    private(set) var rating: TeacherRating?
    private(set) var suspended = false
    private(set) var isAdmin = false
    private(set) var loading = true
    private(set) var working = false
    private(set) var message: String?
    private(set) var error: String?
    private let client = SupabaseService.client

    struct Contact: Codable, Sendable {
        let id: UUID
        let phone: String?
        let fatherName: String?
        let fatherPhone: String?
        let motherName: String?
        let motherPhone: String?
        let familyStatus: String?
        let suspendedReason: String?
        let familyCode: String?
        enum CodingKeys: String, CodingKey {
            case id, phone
            case fatherName = "father_name"; case fatherPhone = "father_phone"
            case motherName = "mother_name"; case motherPhone = "mother_phone"
            case familyStatus = "family_status"; case suspendedReason = "suspended_reason"; case familyCode = "family_code"
        }
    }
    struct TeacherRating: Codable, Sendable { let average: Double?; let count: Int? }
    struct LinkRow3: Codable { let parent_id: UUID; let student_id: UUID }

    func load(_ person: Profile) async {
        suspended = person.isSuspended
        isAdmin = person.role == .admin
        do {
            let contacts: [Contact] = (try? await client.rpc("profile_contacts", params: ["p_ids": [person.id.uuidString]]).execute().value) ?? []
            contact = contacts.first
            switch person.role {
            case .student:
                let links: [LinkRow3] = (try? await client.from("parent_children").select("parent_id, student_id").eq("student_id", value: person.id).execute().value) ?? []
                parents = (try? await DarsData.profiles(ids: links.map { $0.parent_id })) ?? []
                let rows: [ClassMemberRow] = (try? await client.from("class_members").select("class_id, user_id").eq("user_id", value: person.id).execute().value) ?? []
                classes = (try? await DarsData.allClasses()) ?? []
                klass = rows.first.flatMap { r in classes.first { $0.id == r.classId } }
            case .parent:
                let links: [LinkRow3] = (try? await client.from("parent_children").select("parent_id, student_id").eq("parent_id", value: person.id).execute().value) ?? []
                children = (try? await DarsData.profiles(ids: links.map { $0.student_id })) ?? []
            case .teacher, .admin:
                taught = (try? await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: person.id).execute().value) ?? []
                classes = (try? await DarsData.allClasses()) ?? []
                do {
                    let r: TeacherRating = try await client.rpc("teacher_ratings_for", params: ["p_teacher": person.id.uuidString]).execute().value
                    rating = r
                } catch {}
            }
        }
        loading = false
    }

    private func run(_ what: String, _ job: () async throws -> Void) async {
        working = true
        error = nil
        message = nil
        defer { working = false }
        do {
            try await job()
            message = what
            HapticEngine.play(.success)
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }

    struct SuspendArgs: Encodable { let p_user: UUID; let p_suspended: Bool; let p_reason: String? }
    struct AdminArgs: Encodable { let p_user: UUID; let p_is_admin: Bool }

    func setSuspended(_ person: Profile, _ on: Bool, reason: String?) async {
        await run(on ? "Account paused" : "Account active again") {
            try await client.rpc("admin_set_suspended", params: SuspendArgs(p_user: person.id, p_suspended: on, p_reason: reason)).execute()
        }
        if error == nil { suspended = on }
    }

    func setAdmin(_ person: Profile, _ on: Bool) async {
        await run(on ? "Now an admin" : "No longer an admin") {
            try await client.rpc("set_school_admin", params: AdminArgs(p_user: person.id, p_is_admin: on)).execute()
        }
        if error == nil { isAdmin = on }
    }

    func unlink(student: UUID, parent: UUID) async {
        await run("Unlinked") {
            try await client.rpc("admin_unlink_parent", params: ["p_student": student.uuidString, "p_parent": parent.uuidString]).execute()
        }
        if error == nil {
            parents.removeAll { $0.id == parent }
            children.removeAll { $0.id == student }
        }
    }

    func saveFamily(_ student: UUID, father: String, fatherPhone: String, mother: String, motherPhone: String, status: String) async {
        await run("Family saved") {
            try await client.rpc("admin_set_student_family", params: [
                "p_student": student.uuidString, "p_father_name": father, "p_father_phone": fatherPhone,
                "p_mother_name": mother, "p_mother_phone": motherPhone, "p_family_status": status,
            ]).execute()
        }
        if error == nil {
            contact = Contact(id: student, phone: contact?.phone, fatherName: father, fatherPhone: fatherPhone, motherName: mother, motherPhone: motherPhone, familyStatus: status, suspendedReason: contact?.suspendedReason, familyCode: contact?.familyCode)
        }
    }

    func transfer(_ student: UUID, to klassId: UUID) async {
        await run("Moved class") {
            try await client.rpc("transfer_student", params: ["p_student": student.uuidString, "p_to_class": klassId.uuidString]).execute()
        }
        if error == nil { klass = classes.first { $0.id == klassId } }
    }

    struct NewAssignment: Encodable { let teacher_id: UUID; let class_id: UUID; let subject: String }

    func assign(teacher: Profile, to klassId: UUID, subject: String) async {
        await run("Class assigned") {
            try await client.from("teacher_assignments").insert(NewAssignment(teacher_id: teacher.id, class_id: klassId, subject: subject)).execute()
        }
        if error == nil { taught = (try? await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: teacher.id).execute().value) ?? taught }
    }

    func unassign(_ row: TeacherAssignmentRow) async {
        await run("Class removed") {
            try await client.from("teacher_assignments").delete().eq("id", value: row.id).execute()
        }
        if error == nil { taught.removeAll { $0.id == row.id } }
    }
}

struct AdminPersonView: View {
    let me: Profile
    let person: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = AdminPersonStore()
    @State private var resetting = false
    @State private var editingFamily = false
    @State private var pausing = false
    @State private var assigning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                header
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    if let m = store.message { banner(m, DarsColor.success, "checkmark.circle.fill") }
                    if let e = store.error { banner(e, DarsColor.danger, "exclamationmark.triangle.fill") }
                    account
                    switch person.role {
                    case .student: studentParts
                    case .parent: parentParts
                    case .teacher, .admin: teacherParts
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
            .animation(Motion.arrive, value: store.message)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(person.displayName(kurdish: language.language.isKurdish))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(person) }
        .sheet(isPresented: $resetting) { ResetPasswordSheet(person: person) }
        .sheet(isPresented: $editingFamily) {
            FamilySheet(contact: store.contact) { f, fp, m, mp, st in
                Task { await store.saveFamily(person.id, father: f, fatherPhone: fp, mother: m, motherPhone: mp, status: st) }
            }
        }
        .sheet(isPresented: $assigning) {
            AssignClassSheet(classes: store.classes.filter { c in !store.taught.contains { $0.classId == c.id } }, subject: person.subject ?? "") { cls, subject in
                Task { await store.assign(teacher: person, to: cls, subject: subject) }
            }
        }
        .confirmationDialog(store.suspended ? "Let this account back in?" : "Pause this account?", isPresented: $pausing, titleVisibility: .visible) {
            Button(store.suspended ? "Let them back in" : "Pause the account", role: store.suspended ? nil : .destructive) {
                Task { await store.setSuspended(person, !store.suspended, reason: store.suspended ? nil : "Paused by the office") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.suspended ? "They will be able to post and message again." : "They can still sign in and read, but every write is refused until you lift it.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(url: person.avatarURL, initials: person.avatarInitials ?? String(person.fullName.prefix(1)), color: person.avatarColor, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName(kurdish: language.language.isKurdish)).darsType(.title3).foregroundStyle(DarsColor.labelPrimary)
                Text([roleName, store.klass?.label ?? person.classLabel, person.subject].compactMap { $0 }.joined(separator: " · ")).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                if let phone = store.contact?.phone, !phone.isEmpty {
                    Link(destination: URL(string: "tel:\(phone)")!) {
                        Label(phone, systemImage: "phone.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var roleName: String {
        switch person.role {
        case .student: return "Student"
        case .teacher: return "Teacher"
        case .parent: return "Parent"
        case .admin: return "Admin"
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Account")
            CardList {
                Button { HapticEngine.play(.selection); resetting = true } label: {
                    LinkRow(title: "Set a new password", detail: canReset ? "For when they are locked out" : "An admin cannot reset another admin", symbol: "key.fill")
                }
                .buttonStyle(.plain)
                .disabled(!canReset)
                .opacity(canReset ? 1 : 0.5)
                RowDivider(inset: 62)
                Button { HapticEngine.play(.selection); pausing = true } label: {
                    LinkRow(title: store.suspended ? "Account is paused" : "Pause this account",
                            detail: store.suspended ? (store.contact?.suspendedReason ?? "Writes are refused") : "They keep reading; every write is refused",
                            symbol: store.suspended ? "pause.circle.fill" : "pause.circle",
                            tint: store.suspended ? DarsColor.danger : DarsColor.warning)
                }
                .buttonStyle(.plain)
                if person.role == .teacher || person.role == .admin {
                    RowDivider(inset: 62)
                    Button {
                        HapticEngine.play(.selection)
                        Task { await store.setAdmin(person, !store.isAdmin) }
                    } label: {
                        LinkRow(title: store.isAdmin ? "Remove office access" : "Make them an admin",
                                detail: store.isAdmin ? "They run the school in the app" : "Full access to the school's records",
                                symbol: "building.2.fill", tint: Color(hex: 0x5856D6))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !canReset {
                Text("Two admins resetting each other is how a school gets lost. Ask them to change it themselves in Profile, or remove their office access first.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
            }
        }
    }

    private var canReset: Bool { !(person.role == .admin && person.id != me.id) }

    private var studentParts: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Family")
                CardList {
                    field("Father", store.contact?.fatherName, store.contact?.fatherPhone)
                    RowDivider(inset: Metrics.Space.md)
                    field("Mother", store.contact?.motherName, store.contact?.motherPhone)
                    RowDivider(inset: Metrics.Space.md)
                    field("Status", store.contact?.familyStatus, nil)
                    RowDivider(inset: Metrics.Space.md)
                    Button { HapticEngine.play(.selection); editingFamily = true } label: {
                        LinkRow(title: "Edit family details", symbol: "pencil")
                    }.buttonStyle(.plain)
                }
            }
            if let code = store.contact?.familyCode, !code.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Family code")
                    CodeCard(code: code, caption: "A parent types or scans this once to link themselves to this child.")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Class")
                CardList {
                    Menu {
                        ForEach(store.classes) { c in
                            Button(c.label) { Task { await store.transfer(person.id, to: c.id) } }
                        }
                    } label: {
                        LinkRow(title: "Class", detail: store.klass?.label ?? "Not placed", symbol: "books.vertical.fill")
                    }
                }
                Text("Moving a student takes their whole record with them; a student sits in one class at a time.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Linked parents", trailing: "\(store.parents.count)")
                if store.parents.isEmpty {
                    EmptyCard("No parent has linked to this student yet.")
                } else {
                    CardList {
                        ForEach(Array(store.parents.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { RowDivider() }
                            PersonLine(p, detail: "Parent") {
                                Button("Unlink") { Task { await store.unlink(student: person.id, parent: p.id) } }
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.danger)
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Record")
                CardList {
                    NavigationLink { AttendanceCalendarView(student: person) } label: { LinkRow(title: "Attendance", symbol: "calendar", tint: DarsColor.success) }.buttonStyle(.plain)
                    RowDivider(inset: 62)
                    NavigationLink { MarksView(profile: person) } label: { LinkRow(title: "Report card", symbol: "chart.bar.fill") }.buttonStyle(.plain)
                    RowDivider(inset: 62)
                    NavigationLink { StudentRecordView(student: person) } label: { LinkRow(title: "Full record", detail: "Health, guardian, home, emergency", symbol: "person.text.rectangle", tint: Color(hex: 0x5856D6)) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var parentParts: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Children", trailing: "\(store.children.count)")
            if store.children.isEmpty {
                EmptyCard("This parent has not linked a child yet.")
            } else {
                CardList {
                    ForEach(Array(store.children.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { RowDivider() }
                        PersonLine(c, detail: c.classLabel) {
                            Button("Unlink") { Task { await store.unlink(student: c.id, parent: person.id) } }
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.danger)
                        }
                    }
                }
            }
        }
    }

    private var teacherParts: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            HStack(spacing: 10) {
                StatTile(value: String(store.taught.count), label: "Classes", symbol: "books.vertical.fill")
                StatTile(value: store.rating?.average.map { String(format: "%.1f", $0) } ?? "—", label: "Rating", symbol: "star.fill", tint: DarsColor.warning)
                StatTile(value: String(store.rating?.count ?? 0), label: "Ratings", symbol: "person.2.fill", tint: Color(hex: 0x5856D6))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Teaches")
                if store.taught.isEmpty {
                    EmptyCard("No classes assigned yet.")
                } else {
                    CardList {
                        ForEach(Array(store.taught.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { RowDivider(inset: Metrics.Space.md) }
                            HStack(spacing: 12) {
                                Text(t.classes?.label ?? "—").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(DarsColor.onAccent)
                                    .frame(width: 42, height: 30).background(DarsColor.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(t.subject ?? "—").darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary)
                                Spacer()
                                Button { Task { await store.unassign(t) } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(DarsColor.danger) }
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 9)
                        }
                    }
                }
                Button { HapticEngine.play(.selection); assigning = true } label: {
                    CardList { LinkRow(title: "Assign another class", symbol: "plus.circle.fill", tint: DarsColor.success) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field(_ name: LocalizedStringKey, _ value: String?, _ phone: String?) -> some View {
        HStack {
            Text(name).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—").darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
            if let phone, !phone.isEmpty, let url = URL(string: "tel:\(phone)") {
                Link(destination: url) { Image(systemName: "phone.fill").font(.system(size: 13)).foregroundStyle(DarsColor.accentLabel) }
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12)
    }

    private func banner(_ text: String, _ color: Color, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).darsType(.footnote).foregroundStyle(DarsColor.labelPrimary)
            Spacer()
        }
        .padding(Metrics.Space.md).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct ResetPasswordSheet: View {
    let person: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var password = Self.suggestion()
    @State private var working = false
    @State private var done = false
    @State private var error: String?

    static func suggestion() -> String {
        let words = ["Dars", "Kurd", "Erbil", "Sulay", "Zagros", "Tigris"]
        return (words.randomElement() ?? "Dars") + String(Int.random(in: 1000...9999))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                HStack(spacing: 12) {
                    Avatar(url: person.avatarURL, initials: person.avatarInitials ?? String(person.fullName.prefix(1)), color: person.avatarColor, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.displayName(kurdish: language.language.isKurdish)).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text(person.role.rawValue.capitalized).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    }
                    Spacer()
                }
                if done {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Password changed", systemImage: "checkmark.circle.fill").foregroundStyle(DarsColor.success).darsType(.headline)
                        Text("Tell them this, out loud, and ask them to change it in Profile → Change password.").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                        HStack {
                            Text(password).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(DarsColor.labelPrimary)
                            Spacer()
                            Button { UIPasteboard.general.string = password; HapticEngine.play(.success) } label: { Label("Copy", systemImage: "doc.on.doc").font(.system(size: 14, weight: .semibold)) }
                        }
                        .padding(Metrics.Space.md).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .transition(.opacity)
                } else {
                    Text("A temporary password you say to them in person. At least 6 characters.").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                    HStack(spacing: 8) {
                        TextField("New password", text: $password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 14).frame(height: 52)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button { password = Self.suggestion(); HapticEngine.play(.selection) } label: {
                            Image(systemName: "die.face.5").font(.system(size: 17)).frame(width: 52, height: 52).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                }
                Spacer()
                DarsButton(title: done ? "Done" : "Set this password", kind: done ? .secondary : .primary, systemImage: done ? "checkmark" : "key.fill", isLoading: working, fullWidth: true) {
                    if done { dismiss() } else { Task { await set() } }
                }
                .disabled(!done && password.count < 6)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("New password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .animation(Motion.arrive, value: done)
        }
        .presentationDetents([.medium])
    }

    private func set() async {
        working = true
        error = nil
        defer { working = false }
        struct Body: Encodable { let user_id: String; let password: String }
        struct Reply: Decodable { let ok: Bool?; let error: String? }
        do {
            let reply: Reply = try await SupabaseService.client.functions
                .invoke("admin-reset-password", options: FunctionInvokeOptions(body: Body(user_id: person.id.uuidString, password: password)))
            if reply.ok == true {
                done = true
                HapticEngine.play(.success)
            } else {
                error = Self.explain(reply.error)
                HapticEngine.play(.error)
            }
        } catch {
            self.error = Self.explain(String(describing: error))
            HapticEngine.play(.error)
        }
    }

    static func explain(_ code: String?) -> String {
        guard let code else { return "Couldn't change it." }
        if code.contains("cannot_reset_admin") { return "An admin cannot reset another admin's password." }
        if code.contains("other_school") { return "That person belongs to another school." }
        if code.contains("admins_only") { return "Only an admin can do this." }
        if code.contains("weak_password") { return "Use at least 6 characters." }
        if code.contains("no_such_user") { return "That account no longer exists." }
        return "Couldn't change it. Check the connection and try again."
    }
}

struct FamilySheet: View {
    let contact: AdminPersonStore.Contact?
    let onSave: (String, String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var father = ""
    @State private var fatherPhone = ""
    @State private var mother = ""
    @State private var motherPhone = ""
    @State private var status = "together"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.md) {
                    SectionLabel("Father")
                    DarsField(title: "Name", text: $father)
                    DarsField(title: "Phone", text: $fatherPhone, keyboard: .phonePad)
                    SectionLabel("Mother")
                    DarsField(title: "Name", text: $mother)
                    DarsField(title: "Phone", text: $motherPhone, keyboard: .phonePad)
                    SectionLabel("Family status")
                    Picker("", selection: $status) {
                        Text("Together").tag("together")
                        Text("Separated").tag("separated")
                        Text("Guardian").tag("guardian")
                    }
                    .pickerStyle(.segmented)
                    Text("Only this school's office, the child's own parent and the child see these.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    DarsButton(title: "Save", kind: .primary, systemImage: "checkmark", fullWidth: true) {
                        onSave(father, fatherPhone, mother, motherPhone, status); dismiss()
                    }
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                father = contact?.fatherName ?? ""; fatherPhone = contact?.fatherPhone ?? ""
                mother = contact?.motherName ?? ""; motherPhone = contact?.motherPhone ?? ""
                status = contact?.familyStatus ?? "together"
            }
        }
    }
}

struct AssignClassSheet: View {
    let classes: [ClassRow]
    @State var subject: String
    let onAssign: (UUID, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: UUID?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                DarsField(title: "Subject", text: $subject)
                SectionLabel("Class")
                ScrollView {
                    CardList {
                        ForEach(Array(classes.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { RowDivider(inset: Metrics.Space.md) }
                            Button {
                                HapticEngine.play(.selection)
                                chosen = c.id
                            } label: {
                                HStack {
                                    Text(c.label).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                    Text(c.name ?? "").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                    Spacer()
                                    if chosen == c.id { Image(systemName: "checkmark").foregroundStyle(DarsColor.accentLabel) }
                                }
                                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DarsButton(title: "Assign", kind: .primary, systemImage: "plus", fullWidth: true) {
                    if let chosen { onAssign(chosen, subject.trimmingCharacters(in: .whitespaces)) }
                    dismiss()
                }
                .disabled(chosen == nil || subject.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Assign a class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
