import Foundation
import Observation
import SwiftUI
import Supabase

struct SchoolOverview: Codable, Sendable {
    let students: Int?
    let teachers: Int?
    let parents: Int?
    let classes: Int?
    let todayPresent: Int?
    let todayAbsent: Int?
    let todayLate: Int?
    let todayMarkedClasses: Int?
    let weekRate: Double?
    let marksThisWeek: Int?
    let openReports: Int?
    let announcementsWeek: Int?
    let timetableClasses: Int?
    let unlinkedStudents: Int?
    let perClass: [ClassLine]?

    struct ClassLine: Codable, Identifiable, Sendable {
        let id: UUID
        let label: String?
        let students: Int?
        let attendanceRate: Double?
        let average: Double?
        let timetable: Bool?
        let teachers: Int?
        enum CodingKeys: String, CodingKey {
            case id, label, students, average, timetable, teachers
            case attendanceRate = "attendance_rate"
        }
    }

    enum CodingKeys: String, CodingKey {
        case students, teachers, parents, classes
        case todayPresent = "today_present"
        case todayAbsent = "today_absent"
        case todayLate = "today_late"
        case todayMarkedClasses = "today_marked_classes"
        case weekRate = "week_rate"
        case marksThisWeek = "marks_this_week"
        case openReports = "open_reports"
        case announcementsWeek = "announcements_week"
        case timetableClasses = "timetable_classes"
        case unlinkedStudents = "unlinked_students"
        case perClass = "per_class"
    }
}

struct ActivityItem: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let what: String
    let detail: String?
    let at: Date
}

@MainActor
@Observable
final class AdminOverviewStore {
    private(set) var overview: SchoolOverview?
    private(set) var activity: [ActivityItem] = []
    private(set) var school: SchoolRow?
    private(set) var loading = true
    private(set) var error: String?
    private let client = SupabaseService.client

    struct NewPerson: Codable { let id: UUID; let full_name: String?; let full_name_ku: String?; let role: String?; let created_at: String?; let grade: String? }

    func load(me: Profile) async {
        guard let schoolId = me.schoolId else { loading = false; return }
        do {
            school = try await DarsData.school(schoolId)
            let o: SchoolOverview = try await client.rpc("admin_overview", params: ["p_school": schoolId.uuidString]).execute().value
            overview = o
            await loadActivity()
        } catch { self.error = String(describing: error) }
        loading = false
    }

    private func loadActivity() async {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
        var out: [ActivityItem] = []
        if let people: [NewPerson] = try? await client.from("profiles").select("id, full_name, full_name_ku, role, created_at, grade")
            .order("created_at", ascending: false).limit(8).execute().value {
            for p in people {
                guard let at = p.created_at.map(ISO8601.parse), at > cutoff else { continue }
                out.append(ActivityItem(
                    id: "person-\(p.id)",
                    symbol: p.role == "teacher" ? "person.badge.plus" : "graduationcap.fill",
                    tint: p.role == "teacher" ? Color(hex: 0x5856D6) : DarsColor.success,
                    what: p.full_name ?? "Someone",
                    detail: p.role == "teacher" ? "Joined as a teacher" : (p.grade.map { "Enrolled · Grade \($0)" } ?? "Enrolled"),
                    at: at))
            }
        }
        if let posts: [AnnouncementRow] = try? await client.from("announcements").select(AnnouncementRow.columns)
            .order("created_at", ascending: false).limit(8).execute().value {
            for a in posts {
                guard let at = a.date, at > cutoff else { continue }
                out.append(ActivityItem(id: "post-\(a.id)", symbol: "megaphone.fill", tint: DarsColor.warning, what: a.title ?? "Announcement", detail: "Posted", at: at))
            }
        }
        activity = out.sorted { $0.at > $1.at }.prefix(5).map { $0 }
    }
}

enum AdminRoute: Hashable {
    case people(String)
    case person(Profile)
    case classes
    case classPage(ClassRow)
    case timetable(UUID?)
    case announcements
    case newAnnouncement
    case reports
    case schoolInfo
    case schoolYear
    case newTeacher
    case newStudent
    case record(Profile)
}

struct AdminOverviewView: View {
    let profile: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = AdminOverviewStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    ScreenTitle(title: "Overview", subtitle: store.school?.displayName(kurdish: language.language.isKurdish))
                    NotificationPrimer()
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if let o = store.overview {
                        school(o)
                        today(o)
                        if (o.openReports ?? 0) > 0 || (o.unlinkedStudents ?? 0) > 0 { attention(o) }
                        manage
                        if let rows = o.perClass, !rows.isEmpty { perClass(rows) }
                        if !store.activity.isEmpty { recent }
                    }
                    if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                    Spacer(minLength: 96)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AdminRoute.self) { AdminRouter(route: $0, me: profile) }
            .task { await store.load(me: profile) }
            .refreshable { await store.load(me: profile) }
        }
    }

    private func school(_ o: SchoolOverview) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink(value: AdminRoute.people("students")) { StatTile(value: String(o.students ?? 0), label: "Students", symbol: "graduationcap.fill") }.buttonStyle(.plain)
            NavigationLink(value: AdminRoute.people("teachers")) { StatTile(value: String(o.teachers ?? 0), label: "Teachers", symbol: "person.badge.shield.checkmark", tint: Color(hex: 0x5856D6)) }.buttonStyle(.plain)
            NavigationLink(value: AdminRoute.classes) { StatTile(value: String(o.classes ?? 0), label: "Classes", symbol: "books.vertical.fill", tint: DarsColor.success) }.buttonStyle(.plain)
        }
    }

    private func today(_ o: SchoolOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Today", trailing: "\(o.todayMarkedClasses ?? 0) of \(o.classes ?? 0) classes marked")
            HStack(spacing: 10) {
                StatTile(value: String(o.todayPresent ?? 0), label: "Present", symbol: "checkmark", tint: DarsColor.success)
                StatTile(value: String(o.todayAbsent ?? 0), label: "Absent", symbol: "xmark", tint: DarsColor.danger)
                StatTile(value: String(o.todayLate ?? 0), label: "Late", symbol: "clock", tint: DarsColor.warning)
            }
            HStack(spacing: 10) {
                StatTile(value: o.weekRate.map { "\(Int($0))%" } ?? "—", label: "Attendance this week", symbol: "calendar")
                StatTile(value: String(o.marksThisWeek ?? 0), label: "Marks entered", symbol: "chart.bar.fill", tint: Color(hex: 0x5856D6))
            }
        }
    }

    private func attention(_ o: SchoolOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Needs you")
            CardList {
                if (o.openReports ?? 0) > 0 {
                    NavigationLink(value: AdminRoute.reports) {
                        LinkRow(title: "Open reports", detail: "\(o.openReports ?? 0) waiting on a decision", symbol: "flag.fill", tint: DarsColor.danger)
                    }.buttonStyle(.plain)
                }
                if (o.openReports ?? 0) > 0 && (o.unlinkedStudents ?? 0) > 0 { RowDivider(inset: 62) }
                if (o.unlinkedStudents ?? 0) > 0 {
                    NavigationLink(value: AdminRoute.people("students")) {
                        LinkRow(title: "Students with no parent linked", detail: "\(o.unlinkedStudents ?? 0) of \(o.students ?? 0)", symbol: "figure.2.and.child.holdinghands", tint: DarsColor.warning)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var manage: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Run the school")
            CardList {
                NavigationLink(value: AdminRoute.timetable(nil)) { LinkRow(title: "Timetable", detail: "Bells and the week, per class", symbol: "calendar.badge.clock") }.buttonStyle(.plain)
                RowDivider(inset: 62)
                NavigationLink(value: AdminRoute.announcements) { LinkRow(title: "Announcements", detail: "What the school has said", symbol: "megaphone.fill", tint: DarsColor.warning) }.buttonStyle(.plain)
                RowDivider(inset: 62)
                NavigationLink(value: AdminRoute.schoolYear) { LinkRow(title: "Year & days off", detail: "Semester, term dates, closures", symbol: "calendar") }.buttonStyle(.plain)
                RowDivider(inset: 62)
                NavigationLink(value: AdminRoute.schoolInfo) { LinkRow(title: "School details", detail: "Name, address, who signs", symbol: "building.2.fill") }.buttonStyle(.plain)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Add someone")
            CardList {
                NavigationLink(value: AdminRoute.newStudent) { LinkRow(title: "Add a student", detail: "Enrols them and gives them a password", symbol: "graduationcap.fill", tint: DarsColor.success) }.buttonStyle(.plain)
                RowDivider(inset: 62)
                NavigationLink(value: AdminRoute.newTeacher) { LinkRow(title: "Add a teacher", detail: "Creates the account and its login", symbol: "person.badge.plus", tint: Color(hex: 0x5856D6)) }.buttonStyle(.plain)
                RowDivider(inset: 62)
                NavigationLink(value: AdminRoute.reports) { LinkRow(title: "Reports", detail: "Messages and people reported", symbol: "flag.fill", tint: DarsColor.danger) }.buttonStyle(.plain)
            }
        }
    }

    private func perClass(_ rows: [SchoolOverview.ClassLine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Every class")
            CardList {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowDivider(inset: Metrics.Space.md) }
                    HStack(spacing: 12) {
                        Text(c.label ?? "—").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(DarsColor.onAccent)
                            .frame(width: 44, height: 34).background(DarsColor.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(c.students ?? 0) students").darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
                            HStack(spacing: 6) {
                                if c.timetable != true { tag("No timetable", DarsColor.warning) }
                                if (c.teachers ?? 0) == 0 { tag("No teacher", DarsColor.danger) }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(c.average.map { String(Int($0)) } ?? "—").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(c.average.map { Band($0).color } ?? DarsColor.labelTertiary)
                            Text(c.attendanceRate.map { "\(Int($0))% here" } ?? "—").font(.system(size: 11)).foregroundStyle(DarsColor.labelTertiary)
                        }
                    }
                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 9)
                }
            }
        }
    }

    private func tag(_ text: LocalizedStringKey, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Recent")
            CardList {
                ForEach(Array(store.activity.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { RowDivider(inset: 62) }
                    HStack(spacing: 14) {
                        Image(systemName: a.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(a.tint)
                            .frame(width: 32, height: 32).background(a.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.what).darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                            if let d = a.detail { Text(d).darsType(.caption).foregroundStyle(DarsColor.labelTertiary) }
                        }
                        Spacer()
                        Text(ConversationsView.when(a.at)).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    }
                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                }
            }
        }
    }
}

struct AdminRouter: View {
    let route: AdminRoute
    let me: Profile
    var body: some View {
        switch route {
        case .people(let tab): AdminPeopleView(me: me, tab: tab)
        case .person(let p): AdminPersonView(me: me, person: p)
        case .classes: AdminClassesView(me: me)
        case .classPage(let c): AdminClassView(me: me, klass: c)
        case .timetable(let c): AdminScheduleView(me: me, preselected: c)
        case .announcements: AnnouncementsView(me: me)
        case .newAnnouncement: AnnouncementComposerView(me: me)
        case .reports: ReportsView(me: me)
        case .schoolInfo: SchoolInfoView(me: me)
        case .schoolYear: SchoolYearView(me: me)
        case .newTeacher: NewTeacherView(me: me)
        case .newStudent: NewStudentView(me: me)
        case .record(let p): StudentRecordView(student: p)
        }
    }
}
