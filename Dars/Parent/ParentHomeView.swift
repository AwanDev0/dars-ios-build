import Foundation
import Observation
import SwiftUI
import Supabase

struct ChildSummary: Identifiable, Hashable {
    let profile: Profile
    var today: AttendanceStatus?
    var average: Int?
    var attendanceRate: Int?
    var dueCount: Int
    var weekStars: Double?
    var classId: UUID?
    var id: UUID { profile.id }
}

@MainActor
@Observable
final class ParentHomeStore {
    private(set) var children: [ChildSummary] = []
    private(set) var loading = true
    private(set) var error: DarsError?
    private let client = SupabaseService.client

    struct ChildLink: Codable { let student_id: UUID }
    struct WeekRow: Codable { let week_start: String?; let average: Double?; let teachers: Int? }

    func load(parent: Profile, school: SchoolRow?) async {
        error = nil
        do {
            let links: [ChildLink] = try await client.from("parent_children").select("student_id").eq("parent_id", value: parent.id).execute().value
            let kids = try await DarsData.profiles(ids: links.map { $0.student_id })
            var out: [ChildSummary] = []
            for kid in kids {
                out.append(await summary(kid, semester: school?.semester ?? "1", year: school?.year ?? SchoolYear.current()))
            }
            children = out
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    private func summary(_ kid: Profile, semester: String, year: String) async -> ChildSummary {
        async let today: [AttendanceRow] = (try? await client.from("attendance").select(AttendanceRow.columns)
            .eq("student_id", value: kid.id).eq("date", value: DayKey.string(Date())).limit(1).execute().value) ?? []
        async let all: [AttendanceRow] = (try? await client.from("attendance").select(AttendanceRow.columns)
            .eq("student_id", value: kid.id).limit(400).execute().value) ?? []
        async let report: [ReportRow] = (try? await client.rpc("student_report_card", params: ["p_student": kid.id.uuidString, "p_semester": semester, "p_year": year]).execute().value) ?? []
        async let cls: [StudentClass] = (try? await client.rpc("student_class", params: ["uid": kid.id.uuidString]).execute().value) ?? []
        async let review: [WeekRow] = (try? await client.rpc("student_week_review", params: ["p_student": kid.id.uuidString]).execute().value) ?? []

        let classId = await cls.first?.classId
        var due = 0
        if let classId {
            let work: [Assignment] = (try? await client.from("assignments").select(Assignment.columns).eq("class_id", value: classId).gte("due_date", value: DayKey.string(Date())).execute().value) ?? []
            let done: [Completion] = (try? await client.from("completions").select("id, assignment_id").eq("student_id", value: kid.id).execute().value) ?? []
            let doneIds = Set(done.map { $0.assignmentId })
            due = work.filter { !doneIds.contains($0.id) }.count
        }
        let rows = await all
        let here = rows.filter { $0.status == "present" || $0.status == "late" }.count
        let graded = await report.compactMap { $0.graded ? $0.total : nil }
        return ChildSummary(
            profile: kid,
            today: await today.first.flatMap { AttendanceStatus(rawValue: $0.status) },
            average: graded.isEmpty ? nil : Int((graded.reduce(0, +) / Double(graded.count)).rounded()),
            attendanceRate: rows.isEmpty ? nil : Int((Double(here) * 100 / Double(rows.count)).rounded()),
            dueCount: due,
            weekStars: await review.first?.average,
            classId: classId
        )
    }

    func link(code: String) async -> String? {
        do {
            try await client.rpc("link_child", params: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]).execute()
            HapticEngine.play(.success)
            return nil
        } catch {
            HapticEngine.play(.error)
            let t = String(describing: error)
            if t.contains("unknown_code") { return "No student has that code." }
            if t.contains("wrong_school") { return "That code belongs to another school." }
            return "Couldn't link. Check the code and try again."
        }
    }
}

struct ParentHomeView: View {
    let profile: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = ParentHomeStore()
    @State private var school: SchoolRow?
    @State private var linking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    HStack(alignment: .top) {
                        ScreenTitle(title: "Children", subtitle: school?.displayName(kurdish: language.language.isKurdish))
                        Spacer()
                        Button { linking = true } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(DarsColor.onAccent).frame(width: 36, height: 36).background(DarsColor.accent, in: Circle())
                        }
                        .accessibilityLabel("Link a child")
                    }
                    NotificationPrimer()
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if store.children.isEmpty {
                        ContentUnavailableView {
                            Label("No child linked yet", systemImage: "figure.2.and.child.holdinghands")
                        } description: {
                            Text("Ask the school for your child's family code, then tap + to link them.")
                        } actions: {
                            DarsButton(title: "Link a child", kind: .primary, systemImage: "link") { linking = true }
                        }
                    } else {
                        ForEach(store.children) { child in
                            NavigationLink(value: child) { ChildCard(child: child) }.buttonStyle(.plain)
                        }
                        if store.children.count == 1, let only = store.children.first, let classId = only.classId {
                            SectionLabel("Today")
                            ChildDayView(classId: classId)
                        }
                    }
                    if let error = store.error { error.messageText.darsType(.footnote).foregroundStyle(DarsColor.danger) }
                    Spacer(minLength: 96)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ChildSummary.self) { ChildView(child: $0, school: school) }
            .sheet(isPresented: $linking) {
                LinkChildSheet(store: store) { Task { await store.load(parent: profile, school: school) } }
            }
            .task {
                school = try? await DarsData.school(profile.schoolId)
                await store.load(parent: profile, school: school)
            }
            .refreshable { await store.load(parent: profile, school: school) }
        }
    }
}

extension SchoolRow {
    func displayName(kurdish: Bool) -> String {
        if kurdish, let ku = nameKu, !ku.isEmpty { return ku }
        return name ?? ""
    }
}

struct ChildCard: View {
    let child: ChildSummary
    @Environment(LanguageStore.self) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: 12) {
                Avatar(url: child.profile.avatarURL, initials: child.profile.avatarInitials ?? String(child.profile.fullName.prefix(1)), color: child.profile.avatarColor, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.profile.displayName(kurdish: language.language.isKurdish)).darsType(.title3).foregroundStyle(DarsColor.labelPrimary)
                    Text(child.profile.classLabel.map { "Class \($0)" } ?? "Not placed in a class yet").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                }
                Spacer()
                if let t = child.today {
                    Text(LocalizedStringKey(t.label)).font(.system(size: 12, weight: .bold)).foregroundStyle(t.color)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(t.color.opacity(0.16), in: Capsule())
                } else {
                    Text("Not marked").font(.system(size: 12, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(DarsColor.surfaceGrouped, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                signal(child.average.map(String.init) ?? "—", "Average", child.average.map { Band(Double($0)).color } ?? DarsColor.labelTertiary)
                signal(child.attendanceRate.map { "\($0)%" } ?? "—", "Attendance", (child.attendanceRate ?? 100) < 80 ? DarsColor.warning : DarsColor.success)
                signal(String(child.dueCount), "Due", child.dueCount > 0 ? DarsColor.warning : DarsColor.labelTertiary)
                signal(child.weekStars.map { String(format: "%.1f", $0) } ?? "—", "This week", DarsColor.accentLabel)
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous).strokeBorder(DarsColor.separator, lineWidth: 0.5))
    }

    private func signal(_ value: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.system(size: 10.5)).foregroundStyle(DarsColor.labelTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(DarsColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ChildDayView: View {
    let classId: UUID
    @State private var store = ScheduleStore()
    var body: some View {
        VStack(spacing: 6) {
            if store.loading { ProgressView().frame(maxWidth: .infinity).padding() }
            else if store.items.isEmpty { EmptyCard("No lessons today.") }
            else { ForEach(store.items) { PeriodRow(item: $0) } }
        }
        .task { store.day = ScheduleStore.schoolDay(TodayStore.todayKey()); await store.load(classId: classId) }
    }
}

struct ChildView: View {
    let child: ChildSummary
    let school: SchoolRow?
    @Environment(LanguageStore.self) private var language
    @State private var tab = "today"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Today").tag("today"); Text("Marks").tag("marks"); Text("Attendance").tag("attendance"); Text("Record").tag("record")
            }
            .pickerStyle(.segmented).padding(.horizontal, Metrics.Space.md).padding(.vertical, 8)
            switch tab {
            case "marks":
                MarksView(profile: child.profile)
            case "attendance":
                AttendanceCalendarView(student: child.profile)
            case "record":
                StudentRecordView(student: child.profile, editable: false)
            default:
                ScheduleView(profile: child.profile, classId: child.classId, title: "Timetable")
            }
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(child.profile.displayName(kurdish: language.language.isKurdish))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LinkChildSheet: View {
    let store: ParentHomeStore
    let onLinked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("The family code is on your child's profile at school, or from the office. It links this account to that child and nothing else.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                TextField("Family code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(size: 22, weight: .bold, design: .rounded)).kerning(2)
                    .padding(.horizontal, 14).frame(height: 56)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer()
                DarsButton(title: "Link", kind: .primary, systemImage: "link", isLoading: working, fullWidth: true) {
                    Task {
                        working = true
                        error = await store.link(code: code)
                        working = false
                        if error == nil { onLinked(); dismiss() }
                    }
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Link a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
