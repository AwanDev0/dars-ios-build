import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class TeachersStore {
    struct Teacher: Codable, Identifiable, Sendable {
        let id: UUID
        let name: String?
        let nameKu: String?
        let subject: String?
        let initials: String?
        let avatarUrl: String?
        let avatarColor: String?
        let myStars: Int?
        let myComment: String?
        let myAnonymous: Bool?
        enum CodingKeys: String, CodingKey {
            case id, name, subject, initials
            case nameKu = "name_ku"; case avatarUrl = "avatar_url"; case avatarColor = "avatar_color"
            case myStars = "my_stars"; case myComment = "my_comment"; case myAnonymous = "my_anonymous"
        }
    }

    private(set) var teachers: [Teacher] = []
    private(set) var loading = true
    private(set) var error: String?
    private let client = SupabaseService.client

    struct RateArgs: Encodable { let p_teacher: UUID; let p_stars: Int; let p_comment: String?; let p_anonymous: Bool }

    func load() async {
        do {
            let rows: [Teacher] = try await client.rpc("my_teachers").execute().value
            teachers = rows
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func rate(_ teacher: Teacher, stars: Int, comment: String?, anonymous: Bool) async {
        do {
            try await client.rpc("rate_teacher", params: RateArgs(p_teacher: teacher.id, p_stars: stars, p_comment: comment, p_anonymous: anonymous)).execute()
            HapticEngine.play(.success)
            await load()
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }
}

struct TeachersView: View {
    let profile: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = TeachersStore()
    @State private var rating: TeachersStore.Teacher?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.teachers.isEmpty {
                    ContentUnavailableView("No teachers yet", systemImage: "person.badge.shield.checkmark",
                                           description: Text("Once the office puts teachers on your class's timetable they appear here."))
                } else {
                    CardList {
                        ForEach(Array(store.teachers.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { RowDivider() }
                            Button { HapticEngine.play(.selection); rating = t } label: { row(t) }.buttonStyle(.plain)
                        }
                    }
                    Text("Your stars are anonymous unless you say otherwise. The office sees the average; your teacher never sees who gave what.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("My teachers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(item: $rating) { t in
            RateTeacherSheet(name: language.language.isKurdish ? (t.nameKu ?? t.name ?? "") : (t.name ?? ""),
                             stars: t.myStars ?? 0, comment: t.myComment ?? "", anonymous: t.myAnonymous ?? true) { s, c, a in
                Task { await store.rate(t, stars: s, comment: c, anonymous: a) }
            }
        }
    }

    private func row(_ t: TeachersStore.Teacher) -> some View {
        HStack(spacing: 12) {
            Avatar(url: t.avatarUrl, initials: t.initials ?? String((t.name ?? "?").prefix(1)), color: t.avatarColor, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.language.isKurdish ? (t.nameKu ?? t.name ?? "") : (t.name ?? "")).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                Text(t.subject ?? "").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
            }
            Spacer()
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { s in
                    Image(systemName: s <= (t.myStars ?? 0) ? "star.fill" : "star")
                        .font(.system(size: 12)).foregroundStyle(s <= (t.myStars ?? 0) ? DarsColor.warning : DarsColor.labelTertiary)
                }
            }
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct RateTeacherSheet: View {
    let name: String
    @State var stars: Int
    @State var comment: String
    @State var anonymous: Bool
    let onSave: (Int, String?, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { s in
                        Button {
                            HapticEngine.play(.selection)
                            withAnimation(Motion.arrive) { stars = s }
                        } label: {
                            Image(systemName: s <= stars ? "star.fill" : "star")
                                .font(.system(size: 30)).foregroundStyle(s <= stars ? DarsColor.warning : DarsColor.labelTertiary)
                                .scaleEffect(s == stars ? 1.12 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                TextField("Anything you want to say?", text: $comment, axis: .vertical).lineLimit(3...6)
                    .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Toggle(isOn: $anonymous) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keep my name off it").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text("On: the office sees the stars, not who gave them").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    }
                }
                .tint(DarsColor.accent)
                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                DarsButton(title: "Save", kind: .primary, systemImage: "checkmark", fullWidth: true) {
                    onSave(stars, comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment, anonymous)
                    dismiss()
                }
                .disabled(stars == 0)
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

@MainActor
@Observable
final class ExamsStore {
    struct Line: Identifiable, Hashable {
        let assessment: AssessmentRow
        let score: Double?
        var id: UUID { assessment.id }
        var percent: Double? {
            guard let score, let max = assessment.maxScore, max > 0 else { return nil }
            return score * 100 / max
        }
    }
    private(set) var lines: [Line] = []
    private(set) var loading = true
    private let client = SupabaseService.client

    func load(for profile: Profile, school: SchoolRow?) async {
        do {
            let rows: [StudentClass] = try await client.rpc("student_class", params: ["uid": profile.id.uuidString]).execute().value
            guard let classId = rows.first?.classId else { loading = false; return }
            let all: [AssessmentRow] = try await client.from("assessments_v2").select(AssessmentRow.columns)
                .eq("class_id", value: classId).eq("school_year", value: school?.year ?? SchoolYear.current())
                .order("date", ascending: false).execute().value
            let live = all.filter { $0.archivedAt == nil }
            let scores: [ResultRow] = live.isEmpty ? [] : ((try? await client.from("assessment_results_v2").select("assessment_id, student_id, score")
                .eq("student_id", value: profile.id).in("assessment_id", values: live.map { $0.id.uuidString }).execute().value) ?? [])
            let byId = Dictionary(scores.map { ($0.assessmentId, $0.score) }, uniquingKeysWith: { a, _ in a })
            lines = live.map { Line(assessment: $0, score: byId[$0.id] ?? nil) }
        } catch {}
        loading = false
    }
}

struct ExamsView: View {
    let profile: Profile
    @State private var store = ExamsStore()
    @State private var school: SchoolRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.lines.isEmpty {
                    ContentUnavailableView("No assessments yet", systemImage: "doc.text",
                                           description: Text("Tests and exams your class has had show up here with what you scored."))
                } else {
                    CardList {
                        ForEach(Array(store.lines.enumerated()), id: \.element.id) { i, line in
                            if i > 0 { RowDivider(inset: Metrics.Space.md) }
                            HStack(spacing: 12) {
                                Rectangle().fill(SubjectColor.of(line.assessment.subject)).frame(width: 4, height: 34).clipShape(Capsule())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.assessment.title ?? line.assessment.type?.capitalized ?? "—").darsType(.subheadline).fontWeight(.semibold).foregroundStyle(DarsColor.labelPrimary)
                                    Text([line.assessment.subject, line.assessment.date.map { String($0.prefix(10)) }].compactMap { $0 }.joined(separator: " · "))
                                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                }
                                Spacer()
                                if let score = line.score, let max = line.assessment.maxScore {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text(score == score.rounded() ? String(Int(score)) : String(format: "%.1f", score))
                                            .font(.system(size: 17, weight: .bold)).monospacedDigit()
                                            .foregroundStyle(line.percent.map { Band($0).color } ?? DarsColor.labelPrimary)
                                        Text("/ \(Int(max))").font(.system(size: 11)).foregroundStyle(DarsColor.labelTertiary)
                                    }
                                } else {
                                    Text("Not marked").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                }
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 11)
                        }
                    }
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Tests & exams")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            school = try? await DarsData.school(profile.schoolId)
            await store.load(for: profile, school: school)
        }
    }
}
