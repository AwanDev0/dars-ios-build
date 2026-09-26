import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class AnnouncementsStore {
    private(set) var posts: [AnnouncementRow] = []
    private(set) var seen: [UUID: Int] = [:]
    private(set) var classes: [UUID: ClassRow] = [:]
    private(set) var loading = true
    private(set) var error: String?
    private let client = SupabaseService.client

    struct SeenRow: Codable { let announcement_id: UUID; let seen: Int }
    struct PinPatch: Encodable { let pinned: Bool }

    func load(me: Profile) async {
        do {
            posts = try await client.from("announcements").select(AnnouncementRow.columns).order("created_at", ascending: false).limit(60).execute().value
            if let school = me.schoolId {
                let counts: [SeenRow] = (try? await client.rpc("announcement_seen_counts", params: ["school": school.uuidString]).execute().value) ?? []
                seen = Dictionary(counts.map { ($0.announcement_id, $0.seen) }, uniquingKeysWith: { a, _ in a })
            }
            let ids = Set(posts.compactMap { $0.classId })
            classes = Dictionary((try? await DarsData.classes(ids: Array(ids)))?.map { ($0.id, $0) } ?? [], uniquingKeysWith: { a, _ in a })
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func pin(_ post: AnnouncementRow, _ on: Bool) async {
        HapticEngine.play(.selection)
        do {
            try await client.from("announcements").update(PinPatch(pinned: on)).eq("id", value: post.id).execute()
            if let i = posts.firstIndex(where: { $0.id == post.id }) {
                let p = posts[i]
                posts[i] = AnnouncementRow(id: p.id, schoolId: p.schoolId, authorId: p.authorId, classId: p.classId, scope: p.scope, title: p.title, body: p.body, pinned: on, createdAt: p.createdAt, attachmentUrl: p.attachmentUrl, attachmentName: p.attachmentName)
            }
        } catch { self.error = String(describing: error) }
    }

    func delete(_ post: AnnouncementRow) async {
        do {
            try await client.from("announcements").delete().eq("id", value: post.id).execute()
            withAnimation(Motion.arrive) { posts.removeAll { $0.id == post.id } }
            HapticEngine.play(.success)
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }
}

struct AnnouncementsView: View {
    let me: Profile
    @State private var store = AnnouncementsStore()
    @State private var deleting: AnnouncementRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                NavigationLink(value: AdminRoute.newAnnouncement) {
                    CardList { LinkRow(title: "New announcement", detail: "To the whole school or one class", symbol: "plus.circle.fill", tint: DarsColor.success) }
                }
                .buttonStyle(.plain)
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if store.posts.isEmpty {
                    EmptyCard("Nothing has been announced yet.")
                } else {
                    SectionLabel("Posted", trailing: "\(store.posts.count)")
                    ForEach(store.posts) { p in card(p) }
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(me: me) }
        .refreshable { await store.load(me: me) }
        .confirmationDialog("Delete this announcement?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let d = deleting { Task { await store.delete(d) } }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }

    private func card(_ p: AnnouncementRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: p.pinned == true ? "pin.fill" : "megaphone.fill").font(.system(size: 14)).foregroundStyle(p.pinned == true ? DarsColor.accentLabel : DarsColor.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title ?? "—").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    Text(p.body ?? "").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                tag(p.classId.flatMap { store.classes[$0]?.label } ?? "Whole school")
                if let n = store.seen[p.id] { tag("\(n) read") }
                if let d = p.date { Text(ConversationsView.when(d)).darsType(.caption).foregroundStyle(DarsColor.labelTertiary) }
                Spacer()
                Button { Task { await store.pin(p, !(p.pinned ?? false)) } } label: {
                    Image(systemName: p.pinned == true ? "pin.slash" : "pin").font(.system(size: 14)).foregroundStyle(DarsColor.labelSecondary)
                }
                Button { HapticEngine.play(.warning); deleting = p } label: {
                    Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(DarsColor.danger)
                }
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(DarsColor.labelSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3).background(DarsColor.surfaceGrouped, in: Capsule())
    }
}

struct AnnouncementComposerView: View {
    let me: Profile
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var classId: UUID?
    @State private var classes: [ClassRow] = []
    @State private var pinned = false
    @State private var posting = false
    @State private var posted = false
    @State private var error: String?

    struct NewPost: Encodable {
        let school_id: UUID?; let author_id: UUID; let class_id: UUID?; let scope: String
        let title: String; let body: String; let pinned: Bool
    }
    struct Inserted: Codable { let id: UUID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                SectionLabel("Who hears it")
                ChipRow(items: [(nil as UUID?, "Whole school")] + classes.map { ($0.id as UUID?, $0.label) }, selected: $classId)
                DarsField(title: "Title", text: $title)
                TextField("What do they need to know?", text: $body_, axis: .vertical).lineLimit(4...10)
                    .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Toggle(isOn: $pinned) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pin it").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Text("Stays at the top of everyone's home").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    }
                }
                .tint(DarsColor.accent)
                .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if posted {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DarsColor.success)
                        Text("Posted. Everyone has been told.").darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary)
                    }
                    .padding(Metrics.Space.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DarsColor.success.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    DarsButton(title: "Post it", kind: .primary, systemImage: "paperplane.fill", isLoading: posting, fullWidth: true) { Task { await post() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).count < 2)
                }
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Text("A whole-school announcement notifies every person in the school. One class notifies that class and their parents.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
            .animation(Motion.arrive, value: posted)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("New announcement")
        .navigationBarTitleDisplayMode(.inline)
        .hidesDarsTabBar()
        .task { classes = (try? await DarsData.allClasses()) ?? [] }
    }

    private func post() async {
        posting = true
        defer { posting = false }
        do {
            let rows: [Inserted] = try await SupabaseService.client.from("announcements").insert(
                NewPost(school_id: me.schoolId, author_id: me.id, class_id: classId, scope: classId == nil ? "school" : "class",
                        title: title.trimmingCharacters(in: .whitespaces),
                        body: body_.trimmingCharacters(in: .whitespaces).isEmpty ? title.trimmingCharacters(in: .whitespaces) : body_.trimmingCharacters(in: .whitespaces),
                        pinned: pinned)
            ).select("id").execute().value
            posted = true
            HapticEngine.play(.success)
            if let id = rows.first?.id { DarsData.knock(DarsData.PushPost(table: "announcements", post_id: id)) }
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
        }
    }
}
