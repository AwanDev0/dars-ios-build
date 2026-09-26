import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class ReportsStore {
    struct MessageReport: Identifiable, Hashable {
        let id: UUID
        let messageId: UUID
        let body: String
        let kind: String
        let sender: String
        let senderId: UUID?
        let reporter: String
        let reason: String
        let note: String?
        let at: Date?
        let alreadyRemoved: Bool
    }

    struct PersonReport: Codable, Identifiable, Hashable, Sendable {
        struct Who: Codable, Hashable, Sendable {
            let id: UUID
            let name: String?
            let nameKu: String?
            let role: String?
            let klass: String?
            let initials: String?
            let avatarUrl: String?
            let avatarColor: String?
            let suspended: Bool?
            enum CodingKeys: String, CodingKey {
                case id, name, role, initials, suspended
                case nameKu = "name_ku"; case klass = "class"; case avatarUrl = "avatar_url"; case avatarColor = "avatar_color"
            }
        }
        let id: UUID
        let reason: String
        let note: String?
        let createdAt: String?
        let anonymous: Bool?
        let target: Who
        let reporter: Who?
        enum CodingKeys: String, CodingKey { case id, reason, note, anonymous, target, reporter; case createdAt = "created_at" }
    }

    private(set) var messages: [MessageReport] = []
    private(set) var people: [PersonReport] = []
    private(set) var loading = true
    private(set) var working: Set<UUID> = []
    private(set) var error: String?
    private let client = SupabaseService.client

    struct Embedded: Codable { let id: UUID; let body: String?; let kind: String?; let sender_id: UUID?; let deleted: Bool? }
    struct Row: Codable { let id: UUID; let message_id: UUID; let reporter_id: UUID; let reason: String; let note: String?; let created_at: String?; let messages: Embedded? }
    struct Resolve: Encodable { let resolved_at: String; let resolved_by: UUID; let action: String }
    struct Hide: Encodable { let deleted: Bool; let body: String }
    struct SuspendArgs2: Encodable { let p_user: UUID; let p_suspended: Bool; let p_reason: String? }
    struct ResolvePersonArgs: Encodable { let p_report: UUID; let p_action: String }

    func load(kurdish: Bool) async {
        do {
            let rows: [Row] = try await client.from("message_reports")
                .select("id, message_id, reporter_id, reason, note, created_at, messages(id, body, kind, sender_id, deleted)")
                .is("resolved_at", value: nil).order("created_at", ascending: false).limit(100).execute().value
            let ids = Set(rows.compactMap { $0.messages?.sender_id } + rows.map { $0.reporter_id })
            let profiles = (try? await DarsData.profiles(ids: Array(ids))) ?? []
            let byId = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            messages = rows.map { r in
                MessageReport(
                    id: r.id, messageId: r.message_id,
                    body: r.messages?.body ?? "", kind: r.messages?.kind ?? "text",
                    sender: r.messages?.sender_id.flatMap { byId[$0]?.displayName(kurdish: kurdish) } ?? "—",
                    senderId: r.messages?.sender_id,
                    reporter: byId[r.reporter_id]?.displayName(kurdish: kurdish) ?? "—",
                    reason: r.reason, note: r.note?.isEmpty == true ? nil : r.note,
                    at: r.created_at.map(ISO8601.parse), alreadyRemoved: r.messages?.deleted == true)
            }
            people = (try? await client.rpc("people_reports_open").execute().value) ?? []
        } catch { self.error = String(describing: error) }
        loading = false
    }

    private func decide(_ id: UUID, action: String, first: () async throws -> Void) async {
        working.insert(id)
        defer { working.remove(id) }
        do {
            try await first()
            let me = try await SupabaseService.auth.session.user.id
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
            try await client.from("message_reports").update(Resolve(resolved_at: iso.string(from: Date()), resolved_by: me, action: action)).eq("id", value: id).execute()
            withAnimation(Motion.arrive) { messages.removeAll { $0.id == id } }
            HapticEngine.play(.success)
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }

    func remove(_ r: MessageReport) async {
        await decide(r.id, action: "removed") {
            if !r.alreadyRemoved {
                try await client.from("messages").update(Hide(deleted: true, body: "")).eq("id", value: r.messageId).execute()
            }
        }
    }

    func dismiss(_ r: MessageReport) async { await decide(r.id, action: "dismissed") {} }

    func resolvePerson(_ r: PersonReport, action: String) async {
        working.insert(r.id)
        defer { working.remove(r.id) }
        do {
            if action == "suspended" {
                try await client.rpc("admin_set_suspended", params: SuspendArgs2(p_user: r.target.id, p_suspended: true, p_reason: r.reason)).execute()
            }
            try await client.rpc("resolve_people_report", params: ResolvePersonArgs(p_report: r.id, p_action: action)).execute()
            withAnimation(Motion.arrive) { people.removeAll { $0.id == r.id } }
            HapticEngine.play(.success)
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }
}

struct ReportsView: View {
    let me: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = ReportsStore()
    @State private var tab = "messages"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Picker("", selection: $tab) {
                    Text("Messages · \(store.messages.count)").tag("messages")
                    Text("People · \(store.people.count)").tag("people")
                }
                .pickerStyle(.segmented)
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if tab == "messages" {
                    if store.messages.isEmpty {
                        ContentUnavailableView("Nothing reported", systemImage: "checkmark.shield", description: Text("Reported messages land here with two buttons: remove it, or leave it."))
                    } else {
                        ForEach(store.messages) { r in messageCard(r) }
                    }
                } else {
                    if store.people.isEmpty {
                        ContentUnavailableView("Nobody reported", systemImage: "checkmark.shield", description: Text("Reports about people land here."))
                    } else {
                        ForEach(store.people) { r in personCard(r) }
                    }
                }
                if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(kurdish: language.language.isKurdish) }
        .refreshable { await store.load(kurdish: language.language.isKurdish) }
    }

    private func messageCard(_ r: ReportsStore.MessageReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(r.reason.capitalized).font(.system(size: 11, weight: .bold)).foregroundStyle(DarsColor.danger)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(DarsColor.danger.opacity(0.14), in: Capsule())
                if r.alreadyRemoved {
                    Text("Already hidden").font(.system(size: 11, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(DarsColor.surfaceGrouped, in: Capsule())
                }
                Spacer()
                if let at = r.at { Text(ConversationsView.when(at)).darsType(.caption).foregroundStyle(DarsColor.labelTertiary) }
            }
            Text(r.kind == "text" ? (r.body.isEmpty ? "—" : r.body) : (r.kind == "image" ? "A photo" : "An attachment"))
                .darsType(.subheadline).foregroundStyle(DarsColor.labelPrimary)
                .padding(Metrics.Space.sm).frame(maxWidth: .infinity, alignment: .leading)
                .background(DarsColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("From \(r.sender) · reported by \(r.reporter)").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
            if let note = r.note { Text("“\(note)”").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary) }
            HStack(spacing: 8) {
                action("Remove it", "trash", DarsColor.danger) { Task { await store.remove(r) } }
                action("Leave it", "checkmark", DarsColor.labelSecondary) { Task { await store.dismiss(r) } }
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(store.working.contains(r.id) ? 0.5 : 1)
    }

    private func personCard(_ r: ReportsStore.PersonReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hexString: r.target.avatarColor)).frame(width: 40, height: 40)
                    Text(r.target.initials ?? String((r.target.name ?? "?").prefix(1))).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.language.isKurdish ? (r.target.nameKu ?? r.target.name ?? "") : (r.target.name ?? "")).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    Text([r.target.role?.capitalized, r.target.klass].compactMap { $0 }.joined(separator: " · ")).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                }
                Spacer()
                if r.target.suspended == true {
                    Text("Paused").font(.system(size: 11, weight: .bold)).foregroundStyle(DarsColor.danger)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(DarsColor.danger.opacity(0.15), in: Capsule())
                }
            }
            Text(r.reason.capitalized).font(.system(size: 11, weight: .bold)).foregroundStyle(DarsColor.danger)
                .padding(.horizontal, 7).padding(.vertical, 3).background(DarsColor.danger.opacity(0.14), in: Capsule())
            if let note = r.note, !note.isEmpty { Text("“\(note)”").darsType(.footnote).foregroundStyle(DarsColor.labelSecondary) }
            Text(r.anonymous == true ? "Reported anonymously" : "Reported by \(r.reporter?.name ?? "—")").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
            HStack(spacing: 8) {
                action("Pause them", "pause.circle", DarsColor.danger) { Task { await store.resolvePerson(r, action: "suspended") } }
                action("Noted", "text.badge.checkmark", DarsColor.warning) { Task { await store.resolvePerson(r, action: "noted") } }
                action("Dismiss", "xmark", DarsColor.labelSecondary) { Task { await store.resolvePerson(r, action: "dismissed") } }
            }
        }
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(store.working.contains(r.id) ? 0.5 : 1)
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String, _ tint: Color, _ run: @escaping () -> Void) -> some View {
        Button { HapticEngine.play(.selection); run() } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
