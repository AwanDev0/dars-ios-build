import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class AdminClassesStore {
    struct Line: Identifiable, Hashable {
        let klass: ClassRow
        var students: Int
        var teachers: Int
        var hasTimetable: Bool
        var joinCode: String?
        var id: UUID { klass.id }
    }

    private(set) var lines: [Line] = []
    private(set) var loading = true
    private(set) var working = false
    private(set) var error: String?
    private let client = SupabaseService.client

    struct TaRow: Codable { let class_id: UUID? }
    struct SlotRow: Codable { let class_id: UUID? }
    struct CodeRow: Codable { let id: UUID; let join_code: String? }
    struct CreateArgs: Encodable { let p_grade: String; let p_section: String }

    func load() async {
        do {
            let classes = try await DarsData.allClasses()
            async let counts = try await DarsData.memberCounts(classIds: classes.map { $0.id })
            async let staff: [TaRow] = (try? await client.from("teacher_assignments").select("class_id").execute().value) ?? []
            async let slots: [SlotRow] = (try? await client.from("schedule_items").select("class_id").execute().value) ?? []
            async let codes: [CodeRow] = (try? await client.rpc("class_join_codes", params: ["p_classes": classes.map { $0.id.uuidString }]).execute().value) ?? []

            let byStaff = Dictionary(grouping: try await staff.compactMap { $0.class_id }, by: { $0 }).mapValues { $0.count }
            let withTable = Set(try await slots.compactMap { $0.class_id })
            let codeOf = Dictionary(try await codes.map { ($0.id, $0.join_code) }, uniquingKeysWith: { a, _ in a })
            let memberCounts = try await counts
            lines = classes.map { c in
                Line(klass: c, students: memberCounts[c.id] ?? 0, teachers: byStaff[c.id] ?? 0, hasTimetable: withTable.contains(c.id), joinCode: codeOf[c.id] ?? nil)
            }
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func create(grade: String, section: String) async {
        working = true
        defer { working = false }
        do {
            try await client.rpc("admin_create_class", params: CreateArgs(p_grade: grade, p_section: section.uppercased())).execute()
            HapticEngine.play(.success)
            await load()
        } catch {
            self.error = String(describing: error).contains("duplicate") ? "That class already exists." : String(describing: error)
            HapticEngine.play(.error)
        }
    }

    func delete(_ line: Line) async {
        do {
            try await client.rpc("admin_delete_class", params: ["p_class": line.id.uuidString]).execute()
            withAnimation(Motion.arrive) { lines.removeAll { $0.id == line.id } }
            HapticEngine.play(.success)
        } catch {
            self.error = String(describing: error).contains("not_empty") ? "Move its students out first." : String(describing: error)
            HapticEngine.play(.error)
        }
    }
}

struct AdminClassesView: View {
    let me: Profile
    @State private var store = AdminClassesStore()
    @State private var creating = false
    @State private var deleting: AdminClassesStore.Line?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.lines.isEmpty {
                    ContentUnavailableView("No classes yet", systemImage: "books.vertical", description: Text("Make the school's first class; students join it with its code."))
                } else {
                    SectionLabel("Classes", trailing: "\(store.lines.count)")
                    ForEach(store.lines) { line in card(line) }
                }
                Button { HapticEngine.play(.selection); creating = true } label: {
                    CardList { LinkRow(title: "New class", detail: "A grade and a section, like 10 A", symbol: "plus.circle.fill", tint: DarsColor.success) }
                }
                .buttonStyle(.plain)
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Classes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $creating) {
            NewClassSheet { g, s in Task { await store.create(grade: g, section: s) } }
        }
        .confirmationDialog("Delete this class?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = deleting { Task { await store.delete(d) } }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its timetable goes with it. A class with students in it cannot be deleted.")
        }
    }

    private func card(_ line: AdminClassesStore.Line) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: AdminRoute.classPage(line.klass)) {
                HStack(spacing: 12) {
                    Text(line.klass.label).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(DarsColor.onAccent)
                        .frame(width: 52, height: 52).background(DarsColor.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.klass.name ?? line.klass.label).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text("\(line.students) students · \(line.teachers) teachers").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                        HStack(spacing: 6) {
                            if !line.hasTimetable { flag("No timetable", DarsColor.warning) }
                            if line.teachers == 0 { flag("No teacher", DarsColor.danger) }
                            if let c = line.joinCode { flag(LocalizedStringKey(c), DarsColor.labelTertiary) }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                NavigationLink(value: AdminRoute.timetable(line.id)) {
                    Label("Timetable", systemImage: "calendar.badge.clock").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 36).background(DarsColor.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(role: .destructive) { HapticEngine.play(.warning); deleting = line } label: {
                    Label("Delete", systemImage: "trash").font(.system(size: 12, weight: .semibold)).foregroundStyle(DarsColor.danger)
                        .frame(maxWidth: .infinity).frame(height: 36).background(DarsColor.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
    }

    private func flag(_ text: LocalizedStringKey, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
    }
}

struct NewClassSheet: View {
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grade = ""
    @State private var section = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("A class is a grade and a section: 10 and A make 10A. The join code is made for you.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                HStack(spacing: 10) {
                    DarsField(title: "Grade", text: $grade, keyboard: .numberPad)
                    DarsField(title: "Section", text: $section, capitalization: .characters)
                }
                if !grade.isEmpty || !section.isEmpty {
                    Text("This makes \(grade)\(section.uppercased())").darsType(.footnote).foregroundStyle(DarsColor.accentLabel)
                }
                Spacer()
                DarsButton(title: "Create the class", kind: .primary, systemImage: "plus", fullWidth: true) {
                    onCreate(grade.trimmingCharacters(in: .whitespaces), section.trimmingCharacters(in: .whitespaces)); dismiss()
                }
                .disabled(grade.isEmpty || section.isEmpty)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("New class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

@MainActor
@Observable
final class AdminClassStore {
    private(set) var students: [Profile] = []
    private(set) var teachers: [ClassTeacherRow] = []
    private(set) var today: [ScheduleItem] = []
    private(set) var joinCode: String?
    private(set) var loading = true
    private let client = SupabaseService.client

    func load(_ classId: UUID) async {
        do {
            async let roster = try await DarsData.members(classId: classId)
            async let staff: [ClassTeacherRow] = (try? await client.rpc("class_teachers", params: ["p_class": classId.uuidString]).execute().value) ?? []
            async let periods: [ScheduleItem] = (try? await client.from("schedule_items").select(ScheduleItem.columns)
                .eq("class_id", value: classId).eq("day_of_week", value: TodayStore.todayKey()).order("sort_order").execute().value) ?? []
            async let codes: [AdminClassesStore.CodeRow] = (try? await client.rpc("class_join_codes", params: ["p_classes": [classId.uuidString]]).execute().value) ?? []
            students = try await roster.filter { $0.role == .student }
            teachers = try await staff
            today = try await periods
            joinCode = try await codes.first?.join_code
        } catch {}
        loading = false
    }
}

struct AdminClassView: View {
    let me: Profile
    let klass: ClassRow
    @Environment(LanguageStore.self) private var language
    @State private var store = AdminClassStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    HStack(spacing: 10) {
                        StatTile(value: String(store.students.count), label: "Students", symbol: "graduationcap.fill")
                        StatTile(value: String(store.teachers.count), label: "Teachers", symbol: "person.badge.shield.checkmark", tint: Color(hex: 0x5856D6))
                        StatTile(value: String(store.today.filter { !$0.isBreak }.count), label: "Lessons today", symbol: "calendar", tint: DarsColor.success)
                    }
                    CardList {
                        NavigationLink(value: AdminRoute.timetable(klass.id)) { LinkRow(title: "Timetable", detail: "Set the week for this class", symbol: "calendar.badge.clock") }.buttonStyle(.plain)
                    }
                    if let code = store.joinCode {
                        SectionLabel("Join code")
                        CodeCard(code: code)
                    }
                    if !store.today.isEmpty {
                        SectionLabel("Today")
                        VStack(spacing: 6) { ForEach(store.today) { PeriodRow(item: $0) } }
                    }
                    if !store.teachers.isEmpty {
                        SectionLabel("Teachers")
                        CardList {
                            ForEach(Array(store.teachers.enumerated()), id: \.element.id) { i, t in
                                if i > 0 { RowDivider() }
                                HStack(spacing: 12) {
                                    Avatar(url: t.avatarUrl, initials: t.avatarInitials ?? String((t.fullName ?? "?").prefix(1)), color: t.avatarColor, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(language.language.isKurdish ? (t.fullNameKu ?? t.fullName ?? "") : (t.fullName ?? "")).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                        Text(t.subject ?? "").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                            }
                        }
                    }
                    SectionLabel("Students", trailing: "\(store.students.count)")
                    if store.students.isEmpty {
                        EmptyCard("Nobody has joined with the code yet.")
                    } else {
                        CardList {
                            ForEach(Array(store.students.enumerated()), id: \.element.id) { i, p in
                                if i > 0 { RowDivider() }
                                NavigationLink(value: AdminRoute.person(p)) {
                                    PersonLine(p, detail: p.isSuspended ? "Paused" : nil) {
                                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(klass.name ?? klass.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(klass.id) }
    }
}
