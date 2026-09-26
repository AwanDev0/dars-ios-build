import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class WeeklyReviewStore {
    struct Line: Identifiable, Hashable {
        let student: Profile
        var rating: Int
        var note: String
        var changed = false
        var id: UUID { student.id }
    }

    private(set) var classes: [ClassRow] = []
    private(set) var lines: [Line] = []
    private(set) var loading = true
    private(set) var saving = false
    private(set) var saved = false
    private(set) var error: String?
    var classId: UUID?
    private let client = SupabaseService.client

    var weekStart: Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        return cal.date(byAdding: .day, value: -(weekday - 1), to: Date().startOfDay) ?? Date().startOfDay
    }

    struct ReviewRow: Codable { let studentId: UUID; let rating: Int?; let note: String?
        enum CodingKeys: String, CodingKey { case rating, note; case studentId = "student_id" } }
    struct Upsert: Encodable { let class_id: UUID; let student_id: UUID; let teacher_id: UUID; let week_start: String; let rating: Int; let note: String? }

    func load(me: Profile, preselected: UUID?) async {
        do {
            let rows: [TeacherAssignmentRow] = try await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: me.id).execute().value
            var seen = Set<UUID>()
            classes = rows.compactMap { $0.classes }.filter { seen.insert($0.id).inserted }
                .sorted { ($0.gradeNumber, $0.section ?? "") < ($1.gradeNumber, $1.section ?? "") }
            classId = preselected ?? classes.first?.id
        } catch { self.error = String(describing: error) }
        await loadRoster(me: me)
    }

    func loadRoster(me: Profile) async {
        guard let classId else { lines = []; loading = false; return }
        loading = true
        saved = false
        do {
            let people = try await DarsData.members(classId: classId).filter { $0.role == .student }
            var mine: [ReviewRow] = []
            do {
                mine = try await client.from("weekly_reviews").select("student_id, rating, note")
                    .eq("class_id", value: classId).eq("teacher_id", value: me.id).eq("week_start", value: DayKey.string(weekStart)).execute().value
            } catch {}
            let byId = Dictionary(mine.map { ($0.studentId, $0) }, uniquingKeysWith: { a, _ in a })
            lines = people.map { Line(student: $0, rating: byId[$0.id]?.rating ?? 0, note: byId[$0.id]?.note ?? "") }
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func rate(_ id: UUID, _ stars: Int) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        HapticEngine.play(.selection)
        withAnimation(Motion.selection) {
            lines[i].rating = lines[i].rating == stars ? 0 : stars
            lines[i].changed = true
        }
        saved = false
    }

    func note(_ id: UUID, _ text: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[i].note = text
        lines[i].changed = true
        saved = false
    }

    func save(me: Profile) async {
        guard let classId else { return }
        let rows = lines.filter { $0.rating > 0 && $0.changed }
        guard !rows.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            try await client.from("weekly_reviews").upsert(
                rows.map { Upsert(class_id: classId, student_id: $0.id, teacher_id: me.id, week_start: DayKey.string(weekStart), rating: $0.rating, note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.note) },
                onConflict: "student_id,teacher_id,week_start"
            ).execute()
            for i in lines.indices { lines[i].changed = false }
            saved = true
            HapticEngine.play(.success)
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }

    var rated: Int { lines.filter { $0.rating > 0 }.count }
    var unsaved: Bool { lines.contains { $0.changed && $0.rating > 0 } }
}

struct WeeklyReviewView: View {
    let me: Profile
    var preselected: UUID?
    @Environment(LanguageStore.self) private var language
    @State private var store = WeeklyReviewStore()
    @State private var noting: WeeklyReviewStore.Line?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.classes.count > 1 {
                    ChipRow(items: store.classes.map { ($0.id as UUID?, $0.label) }, selected: Binding(get: { store.classId }, set: { v in
                        store.classId = v; Task { await store.loadRoster(me: me) }
                    }))
                }
                HStack {
                    Text("Week of \(store.weekStart.formatted(.dateTime.day().month(.wide)))").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                    Spacer()
                    Text("\(store.rated)/\(store.lines.count) rated").darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                }
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.lines.isEmpty {
                    EmptyCard("No students in this class yet.")
                } else {
                    CardList {
                        ForEach(Array(store.lines.enumerated()), id: \.element.id) { i, line in
                            if i > 0 { RowDivider() }
                            row(line)
                        }
                    }
                    DarsButton(title: store.saved ? "Saved" : "Save the week", kind: .primary, systemImage: store.saved ? "checkmark" : "tray.and.arrow.down", isLoading: store.saving, fullWidth: true) {
                        Task { await store.save(me: me) }
                    }
                    .disabled(!store.unsaved)
                    Text("Stars are private to the school: the student sees the week's average across their teachers, not who gave what.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Weekly review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(me: me, preselected: preselected) }
        .sheet(item: $noting) { line in
            NoteSheet(name: line.student.displayName(kurdish: language.language.isKurdish), note: line.note) { store.note(line.id, $0) }
        }
    }

    private func row(_ line: WeeklyReviewStore.Line) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Avatar(url: line.student.avatarURL, initials: line.student.avatarInitials ?? String(line.student.fullName.prefix(1)), color: line.student.avatarColor, size: 36)
                Text(line.student.displayName(kurdish: language.language.isKurdish)).darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Button { store.rate(line.id, star) } label: {
                            Image(systemName: star <= line.rating ? "star.fill" : "star")
                                .font(.system(size: 17))
                                .foregroundStyle(star <= line.rating ? DarsColor.warning : DarsColor.labelTertiary)
                                .frame(width: 28, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { HapticEngine.play(.selection); noting = line } label: {
                    Image(systemName: line.note.isEmpty ? "text.bubble" : "text.bubble.fill")
                        .font(.system(size: 15)).foregroundStyle(line.note.isEmpty ? DarsColor.labelTertiary : DarsColor.accentLabel)
                }
                .buttonStyle(.plain)
            }
            if !line.note.isEmpty {
                Text(line.note).darsType(.caption).foregroundStyle(DarsColor.labelSecondary).padding(.leading, 46).lineLimit(2)
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 8)
    }
}

struct NoteSheet: View {
    let name: String
    @State var note: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                TextField("A line about this week", text: $note, axis: .vertical).lineLimit(3...6)
                    .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("The school and the student's parent can read this. Write it as you would say it to them.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                Spacer()
                DarsButton(title: "Keep", kind: .primary, systemImage: "checkmark", fullWidth: true) { onSave(note); dismiss() }
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
