import Foundation
import Observation
import SwiftUI
import Supabase

enum PostKind: String, CaseIterable, Identifiable {
    case homework, quiz, exam, announcement
    var id: String { rawValue }
    var title: String {
        switch self {
        case .homework: return "Homework"
        case .quiz: return "Quiz"
        case .exam: return "Exam"
        case .announcement: return "Notice"
        }
    }
    var symbol: String {
        switch self {
        case .homework: return "book.fill"
        case .quiz: return "questionmark.circle.fill"
        case .exam: return "doc.text.fill"
        case .announcement: return "megaphone.fill"
        }
    }
    var color: Color {
        switch self {
        case .homework: return Color(hex: 0x5856D6)
        case .quiz: return Color(hex: 0xFF9500)
        case .exam: return Color(hex: 0xFF3B30)
        case .announcement: return Color(hex: 0x34C759)
        }
    }
    var dated: Bool { self != .announcement }
    var hex: String {
        switch self {
        case .homework: return "#5856D6"
        case .quiz: return "#FF9500"
        case .exam: return "#FF3B30"
        case .announcement: return "#34C759"
        }
    }
}

@MainActor
@Observable
final class PostComposerStore {
    private(set) var classes: [ClassRow] = []
    private(set) var subjects: [String] = []
    private(set) var posting = false
    private(set) var posted = false
    private(set) var error: String?
    var kind: PostKind = .homework
    var classId: UUID?
    var subject = ""
    var title = ""
    var body = ""
    var due = Date().adding(days: 1)
    private var assignments: [TeacherAssignmentRow] = []
    private let client = SupabaseService.client

    struct NewAssignment: Encodable {
        let class_id: UUID; let teacher_id: UUID; let type: String; let subject: String
        let subject_color: String; let title: String; let description: String?; let due_date: String
    }
    struct NewAnnouncement: Encodable {
        let school_id: UUID?; let author_id: UUID; let class_id: UUID; let scope: String
        let title: String; let body: String; let pinned: Bool
    }
    struct Inserted: Codable { let id: UUID }

    func load(me: Profile) async {
        do {
            assignments = try await client.from("teacher_assignments").select(TeacherAssignmentRow.columns).eq("teacher_id", value: me.id).execute().value
            var seen = Set<UUID>()
            classes = assignments.compactMap { $0.classes }.filter { seen.insert($0.id).inserted }
                .sorted { ($0.gradeNumber, $0.section ?? "") < ($1.gradeNumber, $1.section ?? "") }
            if classId == nil { classId = classes.first?.id }
            refreshSubjects()
        } catch { self.error = String(describing: error) }
    }

    func refreshSubjects() {
        subjects = assignments.filter { $0.classId == classId }.compactMap { $0.subject }.filter { !$0.isEmpty }
        if subject.isEmpty || !subjects.contains(subject) { subject = subjects.first ?? "" }
    }

    var canPost: Bool { classId != nil && title.trimmingCharacters(in: .whitespaces).count >= 2 && !posting }

    func post(me: Profile) async {
        guard let classId, canPost else { return }
        posting = true
        defer { posting = false }
        do {
            let id: UUID
            let table: String
            if kind == .announcement {
                let rows: [Inserted] = try await client.from("announcements").insert(
                    NewAnnouncement(school_id: me.schoolId, author_id: me.id, class_id: classId, scope: "class",
                                    title: title.trimmingCharacters(in: .whitespaces),
                                    body: body.trimmingCharacters(in: .whitespaces).isEmpty ? title.trimmingCharacters(in: .whitespaces) : body.trimmingCharacters(in: .whitespaces),
                                    pinned: false)
                ).select("id").execute().value
                guard let first = rows.first else { throw DarsError.server("no row") }
                id = first.id; table = "announcements"
            } else {
                let rows: [Inserted] = try await client.from("assignments").insert(
                    NewAssignment(class_id: classId, teacher_id: me.id, type: kind.rawValue,
                                  subject: subject.isEmpty ? "General" : subject, subject_color: kind.hex,
                                  title: title.trimmingCharacters(in: .whitespaces),
                                  description: body.trimmingCharacters(in: .whitespaces).isEmpty ? nil : body.trimmingCharacters(in: .whitespaces),
                                  due_date: DayKey.string(due))
                ).select("id").execute().value
                guard let first = rows.first else { throw DarsError.server("no row") }
                id = first.id; table = "assignments"
            }
            posted = true
            HapticEngine.play(.success)
            DarsData.knock(DarsData.PushPost(table: table, post_id: id))
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }

    func reset() {
        title = ""; body = ""; posted = false; error = nil
        due = Date().adding(days: 1)
    }
}

struct PostComposerView: View {
    let profile: Profile
    @State private var store = PostComposerStore()
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    ScreenTitle(title: "Post", subtitle: "To one of your classes")
                    kindPicker
                    whereItGoes
                    fields
                    if store.posted {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success)
                            Text("Posted. The class has been told.").darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary)
                            Spacer()
                            Button("Post another") { store.reset() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
                        }
                        .padding(Metrics.Space.md)
                        .background(DarsColor.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        DarsButton(title: "Post to the class", kind: .primary, systemImage: "paperplane.fill", isLoading: store.posting, fullWidth: true) {
                            typing = false
                            Task { await store.post(me: profile) }
                        }
                        .disabled(!store.canPost)
                    }
                    if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                    Text("Everyone in the class gets a notification, and their parents too. Nothing goes to other classes.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    Spacer(minLength: 96)
                }
                .padding(Metrics.Space.md)
                .animation(Motion.arrive, value: store.posted)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
            .task { await store.load(me: profile) }
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(PostKind.allCases) { k in
                Button {
                    HapticEngine.play(.selection)
                    withAnimation(Motion.selection) { store.kind = k }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: k.symbol).font(.system(size: 17, weight: .semibold))
                        Text(k.title).font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(store.kind == k ? .white : k.color)
                    .frame(maxWidth: .infinity).frame(height: 62)
                    .background(store.kind == k ? k.color : k.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var whereItGoes: some View {
        if store.classes.count > 1 {
            SectionLabel("Class")
            ChipRow(items: store.classes.map { ($0.id as UUID?, $0.label) }, selected: Binding(get: { store.classId }, set: { store.classId = $0; store.refreshSubjects() }))
        }
        if store.kind != .announcement, store.subjects.count > 1 {
            SectionLabel("Subject")
            ChipRow(items: store.subjects.map { ($0, $0) }, selected: Binding(get: { store.subject }, set: { store.subject = $0 }))
        }
    }

    @ViewBuilder
    private var fields: some View {
        DarsField(title: store.kind == .announcement ? "What is it about?" : "What is set?", text: Binding(get: { store.title }, set: { store.title = $0 }))
        TextField("More, if it needs it", text: Binding(get: { store.body }, set: { store.body = $0 }), axis: .vertical)
            .lineLimit(3...8).focused($typing)
            .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        if store.kind.dated {
            DatePicker("Due", selection: Binding(get: { store.due }, set: { store.due = $0 }), displayedComponents: .date)
                .padding(.horizontal, 14).frame(height: 50)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
