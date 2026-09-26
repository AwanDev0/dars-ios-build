import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class RegisterStore {
    struct Line: Identifiable, Hashable {
        let student: Profile
        var status: AttendanceStatus?
        var recordId: UUID?
        var note: String?
        var id: UUID { student.id }
    }

    private(set) var classes: [ClassRow] = []
    var classId: UUID?
    var date: Date = Date().startOfDay
    private(set) var lines: [Line] = []
    private(set) var open = true
    private(set) var mayEdit = true
    private(set) var closedReason: String?
    private(set) var loading = true
    private(set) var error: String?
    private let client = SupabaseService.client

    struct DayRow: Codable { let is_open: Bool?; let kind: String?; let reason: String?; let reason_ku: String? }

    func loadClasses(me: Profile, preselected: UUID?) async {
        do {
            let rows: [TeacherAssignmentRow] = try await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: me.id).execute().value
            var seen = Set<UUID>()
            classes = rows.compactMap { $0.classes }.filter { seen.insert($0.id).inserted }
                .sorted { ($0.gradeNumber, $0.section ?? "") < ($1.gradeNumber, $1.section ?? "") }
            classId = preselected ?? classes.first?.id
        } catch { self.error = String(describing: error) }
        await loadRoster(kurdish: false)
    }

    func loadRoster(kurdish: Bool) async {
        guard let classId else { lines = []; loading = false; return }
        loading = true
        let day = DayKey.string(date)
        do {
            async let people = try await DarsData.members(classId: classId)
            async let marks: [AttendanceRow] = (try? await client.from("attendance").select(AttendanceRow.columns).eq("class_id", value: classId).eq("date", value: day).execute().value) ?? []
            async let may: Bool = (try? await client.rpc("can_take_attendance", params: ["p_class": classId.uuidString, "p_date": day]).execute().value) ?? true
            let schoolId = classes.first { $0.id == classId }?.schoolId
            var dayStatus: DayRow? = nil
            if let schoolId {
                let rows: [DayRow] = (try? await client.rpc("school_day_status", params: ["p_school": schoolId.uuidString, "p_date": day]).execute().value) ?? []
                dayStatus = rows.first
            }
            let byStudent = Dictionary(try await marks.map { ($0.studentId, $0) }, uniquingKeysWith: { a, _ in a })
            lines = try await people.filter { $0.role == .student }.map { p in
                let m = byStudent[p.id]
                return Line(student: p, status: m.flatMap { AttendanceStatus(rawValue: $0.status) }, recordId: m?.id, note: m?.note)
            }
            open = dayStatus?.is_open ?? true
            closedReason = open ? nil : (kurdish ? (dayStatus?.reason_ku ?? dayStatus?.reason) : dayStatus?.reason)
            mayEdit = try await may
        } catch { self.error = String(describing: error) }
        loading = false
    }

    struct NewAttendance: Encodable { let student_id: UUID; let class_id: UUID; let teacher_id: UUID; let date: String; let status: String; let note: String? }
    struct Patch: Encodable { let status: String; let note: String? }

    func set(_ student: UUID, to status: AttendanceStatus, note: String? = nil, me: UUID) async {
        guard let classId, mayEdit, open, let i = lines.firstIndex(where: { $0.id == student }) else { return }
        let before = lines[i]
        let next: AttendanceStatus? = (before.status == status && note == nil) ? nil : status
        HapticEngine.play(next == nil ? .selection : (status == .absent ? .warning : .selection))
        withAnimation(Motion.selection) { lines[i].status = next; lines[i].note = note ?? (next == .excused ? before.note : nil) }
        do {
            if next == nil, let rid = before.recordId {
                try await client.from("attendance").delete().eq("id", value: rid).execute()
                lines[i].recordId = nil
            } else if let rid = before.recordId, let next {
                try await client.from("attendance").update(Patch(status: next.rawValue, note: note)).eq("id", value: rid).execute()
            } else if let next {
                let created: [AttendanceRow] = try await client.from("attendance")
                    .insert(NewAttendance(student_id: student, class_id: classId, teacher_id: me, date: DayKey.string(date), status: next.rawValue, note: note))
                    .select(AttendanceRow.columns).execute().value
                if let row = created.first {
                    lines[i].recordId = row.id
                    if (next == .absent || next == .late), Calendar.current.isDateInToday(date) { DarsData.knock(DarsData.PushAbsence(attendance_id: row.id)) }
                }
            }
        } catch {
            lines[i] = before
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }

    func markRestPresent(me: UUID) async {
        for line in lines where line.status == nil { await set(line.id, to: .present, me: me) }
        HapticEngine.play(.success)
    }

    var marked: Int { lines.filter { $0.status != nil }.count }
    func count(_ s: AttendanceStatus) -> Int { lines.filter { $0.status == s }.count }
}

struct AttendanceView: View {
    let me: Profile
    var preselected: UUID?
    @Environment(LanguageStore.self) private var language
    @State private var store = RegisterStore()
    @State private var excusing: RegisterStore.Line?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.classes.count > 1 {
                    ChipRow(items: store.classes.map { ($0.id as UUID?, $0.label) }, selected: Binding(get: { store.classId }, set: { store.classId = $0; Task { await store.loadRoster(kurdish: language.language.isKurdish) } }))
                }
                dateBar
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if !store.open {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(DarsColor.warning)
                        Text(store.closedReason.map { "School closed · \($0)" } ?? "School is closed this day.").darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary)
                    }
                    .padding(Metrics.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DarsColor.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if store.lines.isEmpty {
                    EmptyCard("No students in this class yet.")
                } else {
                    summary
                    if !store.mayEdit {
                        Text("This day is outside what you can mark. The office decides how far back a register may be changed.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    }
                    CardList {
                        ForEach(Array(store.lines.enumerated()), id: \.element.id) { i, line in
                            if i > 0 { RowDivider() }
                            row(line)
                        }
                    }
                    if store.marked < store.lines.count && store.mayEdit {
                        DarsButton(title: "Mark the rest present", kind: .secondary, systemImage: "checkmark.circle", fullWidth: true) { Task { await store.markRestPresent(me: me.id) } }
                    }
                    Text("Hold a name to mark them excused with a reason.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadClasses(me: me, preselected: preselected) }
        .sheet(item: $excusing) { line in
            ExcuseSheet(name: line.student.displayName(kurdish: language.language.isKurdish), note: line.note ?? "") { reason in
                Task { await store.set(line.id, to: .excused, note: reason.isEmpty ? nil : reason, me: me.id) }
            }
        }
    }

    private var dateBar: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36).background(DarsColor.surface, in: Circle()) }
            Spacer()
            VStack(spacing: 1) {
                Text(Calendar.current.isDateInToday(store.date) ? "Today" : store.date.formatted(.dateTime.weekday(.wide))).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                Text(store.date.formatted(.dateTime.day().month(.wide).year())).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36).background(DarsColor.surface, in: Circle()) }
                .disabled(Calendar.current.isDateInToday(store.date) || store.date > Date())
        }
        .foregroundStyle(DarsColor.labelPrimary)
    }

    private func shift(_ by: Int) {
        HapticEngine.play(.selection)
        store.date = store.date.adding(days: by)
        Task { await store.loadRoster(kurdish: language.language.isKurdish) }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            pill(String(store.count(.present)), .present)
            pill(String(store.count(.absent)), .absent)
            pill(String(store.count(.late)), .late)
            pill(String(store.count(.excused)), .excused)
            Spacer()
            Text("\(store.marked)/\(store.lines.count)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DarsColor.labelSecondary)
        }
    }

    private func pill(_ n: String, _ s: AttendanceStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(s.color).frame(width: 7, height: 7)
            Text(n).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5).background(DarsColor.surface, in: Capsule())
    }

    private func row(_ line: RegisterStore.Line) -> some View {
        HStack(spacing: 10) {
            Avatar(url: line.student.avatarURL, initials: line.student.avatarInitials ?? String(line.student.fullName.prefix(1)), color: line.student.avatarColor, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.student.displayName(kurdish: language.language.isKurdish)).darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                if line.status == .excused { Text(line.note ?? "Excused").darsType(.caption).foregroundStyle(AttendanceStatus.excused.color).lineLimit(1) }
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                ForEach([AttendanceStatus.present, .absent, .late]) { s in
                    let on = line.status == s
                    Button {
                        Task { await store.set(line.id, to: s, me: me.id) }
                    } label: {
                        Image(systemName: s.symbol).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(on ? .white : s.color)
                            .frame(width: 34, height: 34)
                            .background(on ? s.color : s.color.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.mayEdit)
                }
                if line.status == .excused {
                    Image(systemName: "doc.text.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 34, height: 34).background(AttendanceStatus.excused.color, in: Circle())
                }
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            guard store.mayEdit else { return }
            HapticEngine.play(.impactMedium)
            excusing = line
        }
        .animation(Motion.selection, value: line.status)
    }
}

struct ExcuseSheet: View {
    let name: String
    @State var note: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("Excused: the school accepts the absence. The reason is what gets quoted back later, so say it plainly.").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                TextField("Reason (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                    .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                DarsButton(title: "Mark excused", kind: .primary, systemImage: "doc.text", fullWidth: true) { onSave(note.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
