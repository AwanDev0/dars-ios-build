import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class WorkStore {
    private(set) var tasks: [Assignment] = []
    private(set) var done: Set<UUID> = []
    private(set) var loading = true
    private(set) var error: DarsError?
    var filter = "open"

    private let client = SupabaseService.client

    func load(for profile: Profile) async {
        error = nil
        do {
            let rows: [StudentClass] = try await client.rpc("student_class", params: ["uid": profile.id.uuidString]).execute().value
            guard let classId = rows.first?.classId else { loading = false; return }
            async let work: [Assignment] = try await client.from("assignments").select(Assignment.columns)
                .eq("class_id", value: classId).order("due_date").execute().value
            async let mine: [Completion] = try await client.from("completions").select("id, assignment_id")
                .eq("student_id", value: profile.id).execute().value
            tasks = try await work
            done = Set(try await mine.map { $0.assignmentId })
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    func toggle(_ task: Assignment, profile: Profile) async {
        HapticEngine.play(done.contains(task.id) ? .selection : .success)
        if done.contains(task.id) {
            done.remove(task.id)
            do { try await client.from("completions").delete().eq("assignment_id", value: task.id).eq("student_id", value: profile.id).execute() } catch { done.insert(task.id) }
        } else {
            done.insert(task.id)
            struct Row: Encodable { let assignment_id: UUID; let student_id: UUID }
            do { try await client.from("completions").insert(Row(assignment_id: task.id, student_id: profile.id)).execute() } catch { done.remove(task.id) }
        }
    }

    var open: [Assignment] { tasks.filter { !done.contains($0.id) } }
    var finished: [Assignment] { tasks.filter { done.contains($0.id) } }
    var exams: [Assignment] { tasks.filter { $0.isExam } }
    var shown: [Assignment] {
        switch filter {
        case "exams": return exams
        case "done": return finished
        default: return open
        }
    }
}

struct Assignment: Codable, Identifiable, Hashable, Sendable {
    static let columns = "id, class_id, type, subject, title, description, due_date, created_at"
    let id: UUID
    let classId: UUID?
    let type: String
    let subject: String
    let title: String
    let description: String?
    let dueDate: String
    let createdAt: String?

    var isExam: Bool { type == "exam" || type == "quiz" }
    var due: Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(dueDate.prefix(10)))
    }

    enum CodingKeys: String, CodingKey {
        case id, type, subject, title, description
        case classId = "class_id"
        case dueDate = "due_date"
        case createdAt = "created_at"
    }
}

struct Completion: Codable, Sendable {
    let id: UUID
    let assignmentId: UUID
    enum CodingKeys: String, CodingKey { case id; case assignmentId = "assignment_id" }
}

struct WorkView: View {
    let profile: Profile
    @State private var store = WorkStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                ScreenTitle(title: "Work", subtitle: store.open.isEmpty ? "Nothing due" : "\(store.open.count) to do")
                ChipRow(items: [("open", "To do"), ("exams", "Exams"), ("done", "Done")], selected: $store.filter)

                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.shown.isEmpty {
                    emptyCard(store.filter == "done" ? "Nothing ticked off yet." : (store.filter == "exams" ? "No exams announced." : "Nothing due. Enjoy it."))
                } else {
                    DarsCard(radius: Metrics.Radius.lg) {
                        VStack(spacing: 0) {
                            ForEach(Array(store.shown.enumerated()), id: \.element.id) { i, t in
                                if i > 0 { Divider().padding(.leading, 62) }
                                taskRow(t, done: store.done.contains(t.id))
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
        .task { await store.load(for: profile) }
        .refreshable { await store.load(for: profile) }
    }

    private func taskRow(_ t: Assignment, done: Bool) -> some View {
        Button {
            Task { await store.toggle(t, profile: profile) }
        } label: {
            HStack(spacing: Metrics.Space.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SubjectColor.of(t.subject).opacity(0.2)).frame(width: 36, height: 36)
                    Image(systemName: t.isExam ? "doc.text.fill" : "book.fill").font(.system(size: 14)).foregroundStyle(SubjectColor.of(t.subject))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary).strikethrough(done, color: DarsColor.labelTertiary).lineLimit(1)
                    Text(t.subject + " · " + dueLabel(t)).darsType(.footnote).foregroundStyle(dueColor(t, done: done)).lineLimit(1)
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? DarsColor.success : DarsColor.labelTertiary)
                    .symbolEffect(.bounce, value: done)
            }
            .padding(Metrics.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dueLabel(_ t: Assignment) -> String {
        guard let d = t.due else { return t.dueDate }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0
        switch days {
        case ..<0: return "was due \(-days)d ago"
        case 0: return "due today"
        case 1: return "due tomorrow"
        default: return "due in \(days) days"
        }
    }
    private func dueColor(_ t: Assignment, done: Bool) -> Color {
        if done { return DarsColor.labelTertiary }
        guard let d = t.due else { return DarsColor.labelSecondary }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0
        return days < 0 ? DarsColor.danger : (days <= 1 ? DarsColor.warning : DarsColor.labelSecondary)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text).darsType(.subheadline).foregroundStyle(DarsColor.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
