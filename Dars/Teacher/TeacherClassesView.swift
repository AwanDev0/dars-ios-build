import Foundation
import Observation
import SwiftUI
import Supabase

struct TeacherClassesView: View {
    let profile: Profile
    @Environment(TeacherStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    ScreenTitle(title: "My classes", subtitle: store.loading ? nil : "\(store.classes.count) classes · \(store.students) students")
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if store.classes.isEmpty {
                        ContentUnavailableView("No classes yet", systemImage: "books.vertical", description: Text("The office assigns you to classes from the timetable. Ask them if this looks wrong."))
                    } else {
                        ForEach(store.classes) { t in ClassCard(taught: t) }
                    }
                    Spacer(minLength: 96)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TeacherRoute.self) { TeacherRouter(route: $0, me: profile) }
            .refreshable { await store.load(me: profile) }
        }
    }
}

struct ClassCard: View {
    let taught: TaughtClass
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            NavigationLink(value: TeacherRoute.classPage(taught)) {
                HStack(spacing: 12) {
                    Text(taught.klass.label).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(DarsColor.onAccent)
                        .frame(width: 56, height: 56).background(DarsColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(taught.klass.name ?? taught.klass.label).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text(taught.subjects.isEmpty ? "—" : taught.subjects.joined(separator: ", ")).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary).lineLimit(1)
                        Text("\(taught.students) students").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                chip("Register", "checklist", DarsColor.success, .attendance(taught.id))
                chip("Marks", "chart.bar.fill", DarsColor.accentLabel, .gradebook(taught.id))
                chip("Students", "person.2.fill", Color(hex: 0x5856D6), .students(taught))
                chip("Review", "star.fill", DarsColor.warning, .review(taught.id))
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
    }

    private func chip(_ title: LocalizedStringKey, _ symbol: String, _ tint: Color, _ route: TeacherRoute) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
@Observable
final class TeacherClassStore {
    private(set) var students: [Profile] = []
    private(set) var today: [String: AttendanceStatus] = [:]
    private(set) var periods: [TeacherPeriod] = []
    private(set) var teachers: [ClassTeacherRow] = []
    private(set) var posts: [Assignment] = []
    private(set) var joinCode: String?
    private(set) var loading = true
    private let client = SupabaseService.client

    func load(classId: UUID, me: UUID) async {
        do {
            async let roster = try await DarsData.members(classId: classId)
            async let marks: [AttendanceRow] = (try? await client.from("attendance").select(AttendanceRow.columns).eq("class_id", value: classId).eq("date", value: DayKey.string(Date())).execute().value) ?? []
            async let mine: [TeacherPeriod] = (try? await client.from("schedule_items").select(TeacherPeriod.columns)
                .eq("class_id", value: classId).eq("teacher_id", value: me).eq("day_of_week", value: TodayStore.todayKey()).order("start_time").execute().value) ?? []
            async let staff: [ClassTeacherRow] = (try? await client.rpc("class_teachers", params: ["p_class": classId.uuidString]).execute().value) ?? []
            async let work: [Assignment] = (try? await client.from("assignments").select(Assignment.columns).eq("class_id", value: classId).order("created_at", ascending: false).limit(10).execute().value) ?? []
            async let code: [CodeRow] = (try? await client.rpc("class_join_codes", params: ["p_classes": [classId.uuidString]]).execute().value) ?? []
            students = try await roster.filter { $0.role == .student }
            today = Dictionary(try await marks.map { ($0.studentId.uuidString, AttendanceStatus(rawValue: $0.status) ?? .present) }, uniquingKeysWith: { a, _ in a })
            periods = try await mine
            teachers = try await staff
            posts = try await work
            joinCode = try await code.first?.joinCode
        } catch {}
        loading = false
    }

    struct CodeRow: Codable { let id: UUID; let joinCode: String?; enum CodingKeys: String, CodingKey { case id; case joinCode = "join_code" } }
    var marked: Int { today.count }
    var absent: Int { today.values.filter { $0 == .absent }.count }
}

struct ClassTeacherRow: Codable, Identifiable, Sendable {
    let teacherId: UUID
    let fullName: String?
    let fullNameKu: String?
    let subject: String?
    let avatarUrl: String?
    let avatarInitials: String?
    let avatarColor: String?
    var id: String { teacherId.uuidString + (subject ?? "") }
    enum CodingKeys: String, CodingKey {
        case subject
        case teacherId = "teacher_id"; case fullName = "full_name"; case fullNameKu = "full_name_ku"; case avatarUrl = "avatar_url"; case avatarInitials = "avatar_initials"; case avatarColor = "avatar_color"
    }
}

struct TeacherClassView: View {
    let me: Profile
    let taught: TaughtClass
    @Environment(LanguageStore.self) private var language
    @State private var store = TeacherClassStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    HStack(spacing: 10) {
                        StatTile(value: String(store.students.count), label: "Students", symbol: "person.2.fill")
                        StatTile(value: store.marked == 0 ? "—" : "\(store.marked)/\(store.students.count)", label: "Marked today", symbol: "checklist", tint: DarsColor.success)
                        StatTile(value: String(store.absent), label: "Absent", symbol: "xmark.circle.fill", tint: DarsColor.danger)
                    }
                    if !store.periods.isEmpty {
                        SectionLabel("My lessons here today")
                        VStack(spacing: 6) {
                            ForEach(store.periods) { p in
                                PeriodRow(item: ScheduleItem(id: p.id, dayOfWeek: p.dayOfWeek, subject: p.subject, teacher: nil, room: p.room, startTime: p.startTime, endTime: p.endTime, isBreak: p.isBreak, sortOrder: p.sortOrder ?? 0))
                            }
                        }
                    }
                    SectionLabel("Do")
                    CardList {
                        NavigationLink(value: TeacherRoute.attendance(taught.id)) { LinkRow(title: "Take the register", detail: store.marked == 0 ? "Not taken yet today" : "\(store.marked) of \(store.students.count) marked", symbol: "checklist", tint: DarsColor.success) }.buttonStyle(.plain)
                        RowDivider(inset: 62)
                        NavigationLink(value: TeacherRoute.gradebook(taught.id)) { LinkRow(title: "Gradebook", detail: taught.subjects.joined(separator: ", "), symbol: "chart.bar.fill") }.buttonStyle(.plain)
                        RowDivider(inset: 62)
                        NavigationLink(value: TeacherRoute.review(taught.id)) { LinkRow(title: "Weekly review", symbol: "star.fill", tint: DarsColor.warning) }.buttonStyle(.plain)
                        RowDivider(inset: 62)
                        NavigationLink(value: TeacherRoute.students(taught)) { LinkRow(title: "Students", detail: "\(store.students.count) in the class", symbol: "person.2.fill", tint: Color(hex: 0x5856D6)) }.buttonStyle(.plain)
                    }
                    if let code = store.joinCode {
                        SectionLabel("Class code")
                        CodeCard(code: code, caption: "Students sign in with this code and their own name. Say it in class; never post it publicly.")
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
                                    if t.teacherId == me.id { Text("You").darsType(.caption).foregroundStyle(DarsColor.accentLabel) }
                                }
                                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                            }
                        }
                    }
                    if !store.posts.isEmpty {
                        SectionLabel("Posted to this class")
                        CardList {
                            ForEach(Array(store.posts.enumerated()), id: \.element.id) { i, a in
                                if i > 0 { RowDivider(inset: 62) }
                                NavigationLink(value: TeacherRoute.receipts(a)) {
                                    LinkRow(title: LocalizedStringKey(a.title), detail: "\(a.subject) · \(a.type.capitalized) · due \(a.dueDate.prefix(10))", symbol: a.isExam ? "doc.text.fill" : "book.fill", tint: SubjectColor.of(a.subject))
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
        .navigationTitle(taught.klass.name ?? taught.klass.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(classId: taught.id, me: me.id) }
        .refreshable { await store.load(classId: taught.id, me: me.id) }
    }
}

struct ClassStudentsView: View {
    let me: Profile
    let taught: TaughtClass
    @State private var store = TeacherClassStore()
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                SearchField(text: $search, prompt: "Search students")
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if shown.isEmpty {
                    EmptyCard("No students match.")
                } else {
                    CardList {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { RowDivider() }
                            NavigationLink(value: TeacherRoute.student(p, taught.id)) {
                                PersonLine(p, detail: p.classLabel) {
                                    if let s = store.today[p.id.uuidString] {
                                        Text(LocalizedStringKey(s.label)).font(.system(size: 12, weight: .bold)).foregroundStyle(s.color)
                                            .padding(.horizontal, 8).padding(.vertical, 4).background(s.color.opacity(0.14), in: Capsule())
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("\(taught.klass.label) · Students")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(classId: taught.id, me: me.id) }
    }

    private var shown: [Profile] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? store.students : store.students.filter { $0.fullName.lowercased().contains(q) || ($0.fullNameKu ?? "").contains(q) }
    }
}

struct TeacherStudentView: View {
    let me: Profile
    let student: Profile
    let classId: UUID
    @Environment(LanguageStore.self) private var language
    @State private var tab = "marks"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(url: student.avatarURL, initials: student.avatarInitials ?? String(student.fullName.prefix(1)), color: student.avatarColor, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName(kurdish: language.language.isKurdish)).darsType(.title3).foregroundStyle(DarsColor.labelPrimary)
                    Text(student.classLabel ?? "").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, Metrics.Space.md).padding(.top, 8)
            Picker("", selection: $tab) { Text("Marks").tag("marks"); Text("Attendance").tag("attendance"); Text("Work").tag("work") }
                .pickerStyle(.segmented).padding(Metrics.Space.md)
            switch tab {
            case "attendance": AttendanceCalendarView(student: student)
            case "work": StudentWorkList(student: student, classId: classId)
            default: MarksView(profile: student)
            }
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StudentWorkList: View {
    let student: Profile
    let classId: UUID
    @State private var work: [Assignment] = []
    @State private var done: Set<UUID> = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else if work.isEmpty { EmptyCard("Nothing has been set for this class yet.") }
                else {
                    CardList {
                        ForEach(Array(work.enumerated()), id: \.element.id) { i, a in
                            if i > 0 { RowDivider(inset: Metrics.Space.md) }
                            HStack(spacing: 12) {
                                Image(systemName: done.contains(a.id) ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(done.contains(a.id) ? DarsColor.success : DarsColor.labelTertiary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                                    Text("\(a.subject) · due \(a.dueDate.prefix(10))").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11)
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .task {
            do {
                let w: [Assignment] = try await SupabaseService.client.from("assignments").select(Assignment.columns).eq("class_id", value: classId).order("due_date", ascending: false).execute().value
                let d: [Completion] = try await SupabaseService.client.from("completions").select("id, assignment_id").eq("student_id", value: student.id).execute().value
                work = w; done = Set(d.map { $0.assignmentId })
            } catch {}
            loading = false
        }
    }
}

struct ReceiptsView: View {
    let assignment: Assignment
    @State private var people: [Profile] = []
    @State private var done: [UUID: Date] = [:]
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment.title).darsType(.title2).foregroundStyle(DarsColor.labelPrimary)
                    Text("\(assignment.subject) · \(assignment.type.capitalized) · due \(assignment.dueDate.prefix(10))").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                    if let d = assignment.description, !d.isEmpty { Text(d).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary).padding(.top, 4) }
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else {
                    SectionLabel("Handed in", trailing: "\(done.count) of \(people.count)")
                    CardList {
                        ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { RowDivider() }
                            PersonLine(p, detail: done[p.id].map { "Done · " + ConversationsView.when($0) }) {
                                Image(systemName: done[p.id] != nil ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(done[p.id] != nil ? DarsColor.success : DarsColor.labelTertiary)
                            }
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                if let cls = assignment.classId { people = try await DarsData.members(classId: cls).filter { $0.role == .student } }
                let rows: [TeacherStore.CompletionFull] = try await SupabaseService.client.from("completions").select("id, assignment_id, student_id, completed_at").eq("assignment_id", value: assignment.id).execute().value
                done = Dictionary(rows.map { ($0.student_id, $0.completed_at.map(ISO8601.parse) ?? Date()) }, uniquingKeysWith: { a, _ in a })
            } catch {}
            loading = false
        }
    }
}
