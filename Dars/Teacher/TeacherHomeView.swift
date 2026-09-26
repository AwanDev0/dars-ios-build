import Foundation
import Observation
import SwiftUI
import Supabase

struct TaughtClass: Identifiable, Hashable {
    let klass: ClassRow
    var subjects: [String]
    var students: Int
    var id: UUID { klass.id }
}

struct TeacherPeriod: Codable, Identifiable, Sendable {
    static let columns = "id, class_id, day_of_week, subject, room, start_time, end_time, is_break, sort_order, classes(id, name, grade, section, school_id)"
    let id: UUID
    let classId: UUID?
    let dayOfWeek: String?
    let subject: String?
    let room: String?
    let startTime: String?
    let endTime: String?
    let isBreak: Bool
    let sortOrder: Int?
    let classes: ClassRow?
    enum CodingKeys: String, CodingKey {
        case id, subject, room, classes
        case classId = "class_id"; case dayOfWeek = "day_of_week"; case startTime = "start_time"; case endTime = "end_time"; case isBreak = "is_break"; case sortOrder = "sort_order"
    }
}

struct HandIn: Identifiable, Hashable {
    let id: UUID
    let student: Profile
    let title: String
    let classLabel: String?
    let at: Date
}

@MainActor
@Observable
final class TeacherStore {
    private(set) var classes: [TaughtClass] = []
    private(set) var today: [TeacherPeriod] = []
    private(set) var handIns: [HandIn] = []
    private(set) var toMark = 0
    private(set) var unread = 0
    private(set) var school: SchoolRow?
    private(set) var loading = true
    private(set) var error: DarsError?
    private let client = SupabaseService.client

    struct CompletionFull: Codable { let id: UUID; let assignment_id: UUID; let student_id: UUID; let completed_at: String? }
    struct IdOnly: Codable { let id: UUID }

    func load(me: Profile) async {
        error = nil
        do {
            async let rows: [TeacherAssignmentRow] = try await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: me.id).execute().value
            async let periods: [TeacherPeriod] = try await client.from("schedule_items").select(TeacherPeriod.columns)
                .eq("teacher_id", value: me.id).eq("day_of_week", value: TodayStore.todayKey()).order("start_time").execute().value
            async let marks: [IdOnly] = (try? await client.from("assessments_v2").select("id").eq("created_by", value: me.id).execute().value) ?? []
            async let sch: SchoolRow? = try? await DarsData.school(me.schoolId)

            var grouped: [UUID: TaughtClass] = [:]
            for r in try await rows {
                guard let c = r.classes else { continue }
                var t = grouped[c.id] ?? TaughtClass(klass: c, subjects: [], students: 0)
                if let s = r.subject, !s.isEmpty, !t.subjects.contains(s) { t.subjects.append(s) }
                grouped[c.id] = t
            }
            let counts = try await DarsData.memberCounts(classIds: Array(grouped.keys))
            classes = grouped.values.map { var t = $0; t.students = counts[t.id] ?? 0; return t }
                .sorted { ($0.klass.gradeNumber, $0.klass.section ?? "") < ($1.klass.gradeNumber, $1.klass.section ?? "") }
            today = try await periods.filter { !$0.isBreak }
            toMark = try await marks.count
            school = await sch
            await loadHandIns(classIds: classes.map { $0.id })
            unread = await unreadCount(me: me.id)
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    private func loadHandIns(classIds: [UUID]) async {
        guard !classIds.isEmpty else { handIns = []; return }
        do {
            let work: [Assignment] = try await client.from("assignments").select(Assignment.columns).in("class_id", values: classIds.map { $0.uuidString }).execute().value
            guard !work.isEmpty else { handIns = []; return }
            let done: [CompletionFull] = try await client.from("completions").select("id, assignment_id, student_id, completed_at")
                .in("assignment_id", values: work.map { $0.id.uuidString }).order("completed_at", ascending: false).limit(8).execute().value
            let people = try await DarsData.profiles(ids: Array(Set(done.map { $0.student_id })))
            let byId = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
            let classById = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0.klass.label) })
            handIns = done.compactMap { d in
                guard let who = byId[d.student_id], let what = work.first(where: { $0.id == d.assignment_id }) else { return nil }
                return HandIn(id: d.id, student: who, title: what.title, classLabel: what.classId.flatMap { classById[$0] }, at: d.completed_at.map(ISO8601.parse) ?? Date())
            }
        } catch { handIns = [] }
    }

    private func unreadCount(me: UUID) async -> Int {
        do {
            let mine: [MemberRow] = try await client.from("conversation_members").select("conversation_id, user_id, muted_at, last_read_at")
                .eq("user_id", value: me).is("left_at", value: nil).execute().value
            guard !mine.isEmpty else { return 0 }
            let convs: [ConversationRow] = try await client.from("conversations").select("id, kind, title, last_message_at, locked_at")
                .in("id", values: mine.map { $0.conversationId.uuidString }).execute().value
            let read = Dictionary(uniqueKeysWithValues: mine.map { ($0.conversationId, $0.lastReadAt) })
            return convs.filter { c in
                guard let last = c.lastMessageAt.map(ISO8601.parse) else { return false }
                guard let r = read[c.id] ?? nil else { return true }
                return last > ISO8601.parse(r)
            }.count
        } catch { return 0 }
    }

    var students: Int { classes.reduce(0) { $0 + $1.students } }
    var next: TeacherPeriod? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"
        let clock = f.string(from: Date())
        return today.first { ($0.endTime ?? "") > clock } ?? today.first
    }
}

enum TeacherRoute: Hashable {
    case attendance(UUID?)
    case gradebook(UUID?)
    case review(UUID?)
    case classPage(TaughtClass)
    case students(TaughtClass)
    case student(Profile, UUID)
    case receipts(Assignment)
    case mySchedule
}

struct TeacherHomeView: View {
    let profile: Profile
    @Environment(LanguageStore.self) private var language
    @Environment(TeacherStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    ScreenTitle(title: "Home", subtitle: greeting)
                    NotificationPrimer()
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else {
                        overview
                        if let p = store.next {
                            SectionLabel("Next class")
                            NavigationLink(value: TeacherRoute.mySchedule) {
                                HStack(spacing: 12) {
                                    Rectangle().fill(SubjectColor.of(p.subject)).frame(width: 5).clipShape(Capsule())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.subject ?? "").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                        Text([p.classes?.label, p.startTime.map { String($0.prefix(5)) }, p.room].compactMap { $0 }.joined(separator: " · ")).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                                }
                                .padding(Metrics.Space.md).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        SectionLabel("Quick actions")
                        CardList {
                            NavigationLink(value: TeacherRoute.attendance(nil)) { LinkRow(title: "Take the register", detail: "Today's attendance, one tap per student", symbol: "checklist", tint: DarsColor.success) }.buttonStyle(.plain)
                            RowDivider(inset: 62)
                            NavigationLink(value: TeacherRoute.gradebook(nil)) { LinkRow(title: "Enter marks", detail: "The four parts, per student", symbol: "chart.bar.fill") }.buttonStyle(.plain)
                            RowDivider(inset: 62)
                            NavigationLink(value: TeacherRoute.review(nil)) { LinkRow(title: "Weekly review", detail: "Five stars per student, once a week", symbol: "star.fill", tint: DarsColor.warning) }.buttonStyle(.plain)
                            RowDivider(inset: 62)
                            NavigationLink(value: TeacherRoute.mySchedule) { LinkRow(title: "My timetable", detail: store.today.isEmpty ? "No lessons today" : "\(store.today.count) lessons today", symbol: "calendar", tint: Color(hex: 0x5856D6)) }.buttonStyle(.plain)
                        }
                        if !store.handIns.isEmpty {
                            SectionLabel("Recent hand-ins")
                            CardList {
                                ForEach(Array(store.handIns.enumerated()), id: \.element.id) { i, h in
                                    if i > 0 { RowDivider() }
                                    PersonLine(h.student, detail: [h.classLabel, h.title].compactMap { $0 }.joined(separator: " · ")) {
                                        Text(ConversationsView.when(h.at)).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                    }
                                }
                            }
                        }
                    }
                    if let error = store.error { error.messageText.darsType(.footnote).foregroundStyle(DarsColor.danger) }
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

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let word = h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
        return "\(word), \(profile.displayName(kurdish: language.language.isKurdish).split(separator: " ").first.map(String.init) ?? "")"
    }

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(value: String(store.classes.count), label: "Classes", symbol: "books.vertical.fill")
            StatTile(value: String(store.students), label: "Students", symbol: "person.2.fill", tint: Color(hex: 0x5856D6))
            StatTile(value: String(store.toMark), label: "Assessments", symbol: "chart.bar.fill", tint: DarsColor.warning)
            StatTile(value: String(store.unread), label: "Unread", symbol: "bubble.left.fill", tint: DarsColor.success)
        }
    }
}

struct TeacherRouter: View {
    let route: TeacherRoute
    let me: Profile
    var body: some View {
        switch route {
        case .attendance(let cls): AttendanceView(me: me, preselected: cls)
        case .gradebook(let cls): GradebookView(me: me, preselected: cls)
        case .review(let cls): WeeklyReviewView(me: me, preselected: cls)
        case .classPage(let t): TeacherClassView(me: me, taught: t)
        case .students(let t): ClassStudentsView(me: me, taught: t)
        case .student(let p, let cls): TeacherStudentView(me: me, student: p, classId: cls)
        case .receipts(let a): ReceiptsView(assignment: a)
        case .mySchedule: TeacherScheduleView(me: me)
        }
    }
}

struct TeacherScheduleView: View {
    let me: Profile
    @State private var week: [String: [TeacherPeriod]] = [:]
    @State private var day = ScheduleStore.schoolDay(TodayStore.todayKey())
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                WeekPicker(day: $day)
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else if (week[day] ?? []).isEmpty { EmptyCard("Nothing on this day.") }
                else {
                    VStack(spacing: 6) {
                        ForEach(week[day] ?? []) { p in
                            PeriodRow(item: ScheduleItem(id: p.id, dayOfWeek: p.dayOfWeek, subject: p.subject, teacher: p.classes?.label, room: p.room, startTime: p.startTime, endTime: p.endTime, isBreak: p.isBreak, sortOrder: p.sortOrder ?? 0))
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("My timetable")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let rows: [TeacherPeriod] = try await SupabaseService.client.from("schedule_items").select(TeacherPeriod.columns)
                    .eq("teacher_id", value: me.id).order("start_time").execute().value
                week = Dictionary(grouping: rows.filter { !$0.isBreak }, by: { $0.dayOfWeek ?? "" })
            } catch {}
            loading = false
        }
    }
}
