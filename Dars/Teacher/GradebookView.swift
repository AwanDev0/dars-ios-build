import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class GradebookStore {
    private(set) var classes: [ClassRow] = []
    private(set) var subjects: [String] = []
    private(set) var rows: [ReportRow2] = []
    private(set) var loading = true
    private(set) var error: String?
    var classId: UUID?
    var subject: String = ""
    var semester = "1"
    private(set) var year = SchoolYear.current()
    private let client = SupabaseService.client

    struct ReportRow2: Codable, Identifiable, Hashable, Sendable {
        let studentId: UUID
        let fullName: String?
        let fullNameKu: String?
        let avatarUrl: String?
        let avatarInitials: String?
        let avatarColor: String?
        let subject: String?
        let c1: Double?
        let c2: Double?
        let c3: Double?
        let final: Double?
        let total: Double?
        let graded: Bool
        var id: String { studentId.uuidString + (subject ?? "") }
        enum CodingKeys: String, CodingKey {
            case subject, c1, c2, c3, final, total, graded
            case studentId = "student_id"; case fullName = "full_name"; case fullNameKu = "full_name_ku"
            case avatarUrl = "avatar_url"; case avatarInitials = "avatar_initials"; case avatarColor = "avatar_color"
        }
    }

    func load(me: Profile, preselected: UUID?) async {
        do {
            let assignments: [TeacherAssignmentRow] = try await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: me.id).execute().value
            var seen = Set<UUID>()
            classes = assignments.compactMap { $0.classes }.filter { seen.insert($0.id).inserted }
                .sorted { ($0.gradeNumber, $0.section ?? "") < ($1.gradeNumber, $1.section ?? "") }
            classId = preselected ?? classes.first?.id
            subjectsFor(assignments: assignments)
            if let school = try? await DarsData.school(me.schoolId) {
                year = school.year
                semester = school.semester
            }
            self.assignments = assignments
        } catch { self.error = String(describing: error) }
        await loadRows()
    }

    private var assignments: [TeacherAssignmentRow] = []

    func subjectsFor(assignments rows: [TeacherAssignmentRow]? = nil) {
        let all = rows ?? assignments
        subjects = all.filter { $0.classId == classId }.compactMap { $0.subject }.filter { !$0.isEmpty }
        if subject.isEmpty || !subjects.contains(subject) { subject = subjects.first ?? "" }
    }

    func loadRows() async {
        guard let classId, !subject.isEmpty else { rows = []; loading = false; return }
        loading = true
        do {
            let all: [ReportRow2] = try await client.rpc("class_report", params: ["p_class": classId.uuidString, "p_semester": semester, "p_year": year]).execute().value
            rows = all.filter { $0.subject == subject }.sorted { ($0.fullName ?? "") < ($1.fullName ?? "") }
        } catch { self.error = String(describing: error) }
        loading = false
    }

    var marked: Int { rows.filter { $0.graded && $0.total != nil }.count }
    var average: Double? {
        let g = rows.compactMap { $0.graded ? $0.total : nil }
        return g.isEmpty ? nil : g.reduce(0, +) / Double(g.count)
    }
}

struct GradebookView: View {
    let me: Profile
    var preselected: UUID?
    @Environment(LanguageStore.self) private var language
    @State private var store = GradebookStore()
    @State private var editing: GradebookStore.ReportRow2?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.classes.count > 1 {
                    ChipRow(items: store.classes.map { ($0.id as UUID?, $0.label) }, selected: Binding(get: { store.classId }, set: { v in
                        store.classId = v; store.subjectsFor(); Task { await store.loadRows() }
                    }))
                }
                if store.subjects.count > 1 {
                    ChipRow(items: store.subjects.map { ($0, $0) }, selected: Binding(get: { store.subject }, set: { v in
                        store.subject = v; Task { await store.loadRows() }
                    }))
                }
                Picker("Semester", selection: Binding(get: { store.semester }, set: { store.semester = $0; Task { await store.loadRows() } })) {
                    Text("Semester 1").tag("1"); Text("Semester 2").tag("2")
                }
                .pickerStyle(.segmented)

                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.rows.isEmpty {
                    EmptyCard("Nothing to mark here yet. The office sets up the class and its subjects.")
                } else {
                    HStack(spacing: 10) {
                        StatTile(value: "\(store.marked)/\(store.rows.count)", label: "Marked", symbol: "checkmark.seal.fill", tint: DarsColor.success)
                        StatTile(value: store.average.map { String(Int($0.rounded())) } ?? "—", label: "Class average", symbol: "chart.bar.fill")
                    }
                    CardList {
                        ForEach(Array(store.rows.enumerated()), id: \.element.id) { i, r in
                            if i > 0 { RowDivider() }
                            Button { HapticEngine.play(.selection); editing = r } label: { row(r) }.buttonStyle(.plain)
                        }
                    }
                    Text("Tap a student to type their four parts. The total is worked out by the school's own rule — 10 · 20 · 10 · 60 — never here.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Gradebook")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(me: me, preselected: preselected) }
        .sheet(item: $editing) { r in
            MarkEntrySheet(me: me, classId: store.classId ?? UUID(), subject: store.subject, semester: store.semester, year: store.year,
                           studentId: r.studentId, name: language.language.isKurdish ? (r.fullNameKu ?? r.fullName ?? "") : (r.fullName ?? ""))
            { Task { await store.loadRows() } }
        }
    }

    private func row(_ r: GradebookStore.ReportRow2) -> some View {
        let band = r.total.map(Band.init)
        return HStack(spacing: 12) {
            Avatar(url: r.avatarUrl, initials: r.avatarInitials ?? String((r.fullName ?? "?").prefix(1)), color: r.avatarColor, size: 38)
            Text(language.language.isKurdish ? (r.fullNameKu ?? r.fullName ?? "") : (r.fullName ?? "")).darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
            Spacer()
            HStack(spacing: 3) {
                part(r.c1, 10); part(r.c2, 20); part(r.c3, 10); part(r.final, 60)
            }
            Text(r.total.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: 17, weight: .bold)).monospacedDigit()
                .foregroundStyle(band?.color ?? DarsColor.labelTertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 9)
    }

    private func part(_ v: Double?, _ max: Int) -> some View {
        Capsule()
            .fill(v == nil ? DarsColor.separator : DarsColor.accent.opacity(0.35 + 0.65 * min(1, (v ?? 0) / Double(max))))
            .frame(width: CGFloat(max) / 2.2, height: 5)
    }
}

@MainActor
@Observable
final class MarkEntryStore {
    struct Field: Identifiable {
        let assessmentId: UUID
        let part: String
        let max: Double
        var entry: String
        var saved = false
        var bad = false
        var id: UUID { assessmentId }
    }

    private(set) var fields: [Field] = []
    private(set) var total: Double?
    private(set) var loading = true
    private(set) var noScheme = false
    private(set) var error: String?
    private let client = SupabaseService.client

    struct SchemeRow: Codable { let officialExamId: UUID?; enum CodingKeys: String, CodingKey { case officialExamId = "official_exam_id" } }
    struct TotalRow: Codable { let total: Double? }
    struct NewScore: Encodable { let assessment_id: UUID; let student_id: UUID; let score: Double; let updated_by: UUID? }

    func load(classId: UUID, subject: String, semester: String, year: String, student: UUID) async {
        loading = true
        _ = try? await client.rpc("ensure_grade_scheme", params: ["p_class": classId.uuidString, "p_subject": subject, "p_semester": semester, "p_year": year]).execute()
        do {
            let all: [AssessmentRow] = try await client.from("assessments_v2").select(AssessmentRow.columns)
                .eq("class_id", value: classId).eq("subject", value: subject).eq("semester", value: semester).eq("school_year", value: year).execute().value
            let live = all.filter { $0.archivedAt == nil }
            if live.isEmpty { noScheme = true; loading = false; return }
            var scheme: [SchemeRow] = []
            do {
                scheme = try await client.from("grade_scheme").select("class_id, subject, semester, school_year, official_exam_id")
                    .eq("class_id", value: classId).eq("subject", value: subject).eq("semester", value: semester).eq("school_year", value: year)
                    .execute().value
            } catch {}
            let official = scheme.first?.officialExamId
            var scores: [ResultRow] = []
            do {
                scores = try await client.from("assessment_results_v2").select("assessment_id, student_id, score")
                    .eq("student_id", value: student).in("assessment_id", values: live.map { $0.id.uuidString }).execute().value
            } catch {}
            let byId = Dictionary(scores.map { ($0.assessmentId, $0.score) }, uniquingKeysWith: { a, _ in a })

            let midterm = live.first { $0.id == official && $0.type == "mini_exam" }
                ?? live.filter { $0.type == "mini_exam" }.min { ($0.date ?? "9999") < ($1.date ?? "9999") }
            func field(_ row: AssessmentRow?, _ part: String, _ fallbackMax: Double) -> Field? {
                guard let row else { return nil }
                let v = byId[row.id] ?? nil
                return Field(assessmentId: row.id, part: part, max: row.maxScore ?? fallbackMax,
                             entry: v.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "")
            }
            fields = [
                field(live.first { $0.type == "component_1" }, "Part 1", 10),
                field(midterm, "Midterm", 20),
                field(live.first { $0.type == "component_3" }, "Part 3", 10),
                field(live.first { $0.type == "final" }, "Final", 60),
            ].compactMap { $0 }
        } catch { self.error = String(describing: error) }
        loading = false
        await refreshTotal(classId: classId, subject: subject, semester: semester, year: year, student: student)
    }

    func type(_ id: UUID, _ text: String) {
        guard let i = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[i].entry = text
        fields[i].saved = false
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        fields[i].bad = !text.isEmpty && (v == nil || v! < 0 || v! > fields[i].max)
    }

    func commit(_ id: UUID, me: UUID, classId: UUID, subject: String, semester: String, year: String, student: UUID) async {
        guard let i = fields.firstIndex(where: { $0.id == id }), !fields[i].bad, !fields[i].entry.isEmpty,
              let score = Double(fields[i].entry.replacingOccurrences(of: ",", with: ".")) else { return }
        do {
            try await client.from("assessment_results_v2")
                .upsert(NewScore(assessment_id: id, student_id: student, score: score, updated_by: me), onConflict: "assessment_id,student_id")
                .execute()
            fields[i].saved = true
            HapticEngine.play(.success)
            await refreshTotal(classId: classId, subject: subject, semester: semester, year: year, student: student)
            DarsData.knock(DarsData.PushGrade(assessment_id: id, student_id: student))
        } catch {
            fields[i].bad = true
            HapticEngine.play(.error)
            self.error = String(describing: error)
        }
    }

    private func refreshTotal(classId: UUID, subject: String, semester: String, year: String, student: UUID) async {
        do {
            let rows: [TotalRow] = try await client.rpc("student_grade", params: [
                "p_class": classId.uuidString, "p_subject": subject, "p_semester": semester, "p_year": year, "p_student": student.uuidString,
            ]).execute().value
            total = rows.first?.total
        } catch {}
    }
}

struct MarkEntrySheet: View {
    let me: Profile
    let classId: UUID
    let subject: String
    let semester: String
    let year: String
    let studentId: UUID
    let name: String
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = MarkEntryStore()
    @FocusState private var focused: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.md) {
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if store.noScheme {
                        ContentUnavailableView("No marking scheme", systemImage: "exclamationmark.triangle", description: Text("This class and subject have no components set up. The office creates them on the class page."))
                    } else {
                        HStack {
                            Text("Total").darsType(.headline).foregroundStyle(DarsColor.labelSecondary)
                            Spacer()
                            Text(store.total.map { String(Int($0.rounded())) } ?? "—")
                                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(store.total.map { Band($0).color } ?? DarsColor.labelTertiary)
                                .contentTransition(.numericText())
                            Text("/100").darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                        }
                        .padding(Metrics.Space.md)
                        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .animation(Motion.moment, value: store.total)

                        ForEach(store.fields) { f in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.part).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                    Text("out of \(Int(f.max))").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                }
                                Spacer()
                                if f.saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success).transition(.scale) }
                                TextField("—", text: Binding(get: { f.entry }, set: { store.type(f.id, $0) }))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                                    .focused($focused, equals: f.id)
                                    .frame(width: 84, height: 48)
                                    .background(DarsColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(f.bad ? DarsColor.danger : (focused == f.id ? DarsColor.accent : .clear), lineWidth: 1.5))
                                    .onSubmit { Task { await store.commit(f.id, me: me.id, classId: classId, subject: subject, semester: semester, year: year, student: studentId) } }
                            }
                            .padding(Metrics.Space.md)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .animation(Motion.selection, value: f.saved)
                        }
                        Text("A mark is saved the moment you leave the box. Out of range turns it red and nothing is written.")
                            .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    }
                    if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let f = focused { Task { await store.commit(f, me: me.id, classId: classId, subject: subject, semester: semester, year: year, student: studentId) } }
                        onClose(); dismiss()
                    }
                }
            }
            .onChange(of: focused) { old, _ in
                if let old { Task { await store.commit(old, me: me.id, classId: classId, subject: subject, semester: semester, year: year, student: studentId) } }
            }
            .task { await store.load(classId: classId, subject: subject, semester: semester, year: year, student: studentId) }
        }
    }
}
