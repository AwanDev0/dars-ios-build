import Foundation
import Observation
import SwiftUI
import Supabase

@MainActor
@Observable
final class NewChatStore {
    struct Contact: Codable, Identifiable, Sendable {
        let id: UUID
        let fullName: String?
        let avatarInitials: String?
        let avatarColor: String?
        let role: String?
        let subject: String?
        enum CodingKeys: String, CodingKey {
            case id, role, subject
            case fullName = "full_name"; case avatarInitials = "avatar_initials"; case avatarColor = "avatar_color"
        }
    }

    struct Requestable: Codable, Identifiable, Sendable {
        let id: UUID
        let fullName: String?
        let fullNameKu: String?
        let avatarInitials: String?
        let avatarColor: String?
        let avatarUrl: String?
        let grade: String?
        let section: String?
        let pending: Bool?
        enum CodingKeys: String, CodingKey {
            case id, grade, section, pending
            case fullName = "full_name"; case fullNameKu = "full_name_ku"
            case avatarInitials = "avatar_initials"; case avatarColor = "avatar_color"; case avatarUrl = "avatar_url"
        }
    }

    struct Request: Codable, Identifiable, Sendable {
        let id: UUID
        let requesterId: UUID
        let fullName: String?
        let fullNameKu: String?
        let avatarInitials: String?
        let avatarColor: String?
        let avatarUrl: String?
        let grade: String?
        let section: String?
        enum CodingKeys: String, CodingKey {
            case id, grade, section
            case requesterId = "requester_id"; case fullName = "full_name"; case fullNameKu = "full_name_ku"
            case avatarInitials = "avatar_initials"; case avatarColor = "avatar_color"; case avatarUrl = "avatar_url"
        }
    }

    private(set) var contacts: [Contact] = []
    private(set) var requestable: [Requestable] = []
    private(set) var requests: [Request] = []
    private(set) var loading = true
    private(set) var working = false
    private(set) var error: String?
    var query = ""
    private let client = SupabaseService.client

    func load() async {
        do {
            async let a: [Contact] = try await client.rpc("list_contacts").execute().value
            async let b: [Requestable] = (try? await client.rpc("list_dm_requestable").execute().value) ?? []
            async let c: [Request] = (try? await client.rpc("list_dm_requests").execute().value) ?? []
            contacts = try await a
            requestable = try await b
            requests = try await c
        } catch { self.error = String(describing: error) }
        loading = false
    }

    func open(_ other: UUID) async -> UUID? {
        working = true
        defer { working = false }
        do {
            let id: UUID = try await client.rpc("start_dm", params: ["other": other.uuidString]).execute().value
            HapticEngine.play(.success)
            return id
        } catch {
            self.error = String(describing: error)
            HapticEngine.play(.error)
            return nil
        }
    }

    func request(_ other: UUID) async {
        working = true
        defer { working = false }
        do {
            _ = try await client.rpc("request_dm", params: ["other": other.uuidString]).execute()
            HapticEngine.play(.success)
            await load()
        } catch { self.error = String(describing: error); HapticEngine.play(.error) }
    }

    func respond(_ request: Request, accept: Bool) async {
        struct Args: Encodable { let req: UUID; let accept: Bool }
        do {
            try await client.rpc("respond_dm_request", params: Args(req: request.id, accept: accept)).execute()
            withAnimation(Motion.arrive) { requests.removeAll { $0.id == request.id } }
            HapticEngine.play(.success)
        } catch { self.error = String(describing: error) }
    }

    var shownContacts: [Contact] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? contacts : contacts.filter { ($0.fullName ?? "").lowercased().contains(q) }
    }
    var shownRequestable: [Requestable] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? requestable : requestable.filter { ($0.fullName ?? "").lowercased().contains(q) || ($0.fullNameKu ?? "").contains(q) }
    }
}

struct NewChatView: View {
    let me: Profile
    let onOpened: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var store = NewChatStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.md) {
                    SearchField(text: Binding(get: { store.query }, set: { store.query = $0 }), prompt: "Search people")

                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else {
                        if !store.requests.isEmpty {
                            SectionLabel("Wants to message you", trailing: "\(store.requests.count)")
                            CardList {
                                ForEach(Array(store.requests.enumerated()), id: \.element.id) { i, r in
                                    if i > 0 { RowDivider() }
                                    HStack(spacing: 12) {
                                        Avatar(url: r.avatarUrl, initials: r.avatarInitials ?? String((r.fullName ?? "?").prefix(1)), color: r.avatarColor, size: 40)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(language.language.isKurdish ? (r.fullNameKu ?? r.fullName ?? "") : (r.fullName ?? "")).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                            Text([r.grade, r.section].compactMap { $0 }.joined()).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                        }
                                        Spacer()
                                        Button("Accept") { Task { await store.respond(r, accept: true) } }
                                            .font(.system(size: 13, weight: .bold)).foregroundStyle(DarsColor.onAccent)
                                            .padding(.horizontal, 12).padding(.vertical, 6).background(DarsColor.accent, in: Capsule())
                                        Button { Task { await store.respond(r, accept: false) } } label: {
                                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(DarsColor.labelTertiary)
                                        }
                                    }
                                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                                }
                            }
                        }

                        if !store.shownContacts.isEmpty {
                            SectionLabel("Message directly")
                            CardList {
                                ForEach(Array(store.shownContacts.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { RowDivider() }
                                    Button {
                                        Task {
                                            if let id = await store.open(c.id) { onOpened(id); dismiss() }
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Avatar(url: nil, initials: c.avatarInitials ?? String((c.fullName ?? "?").prefix(1)), color: c.avatarColor, size: 40)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(c.fullName ?? "").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                                Text([c.role?.capitalized, c.subject].compactMap { $0 }.joined(separator: " · ")).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                            }
                                            Spacer()
                                            Image(systemName: "bubble.left.fill").font(.system(size: 13)).foregroundStyle(DarsColor.accentLabel)
                                        }
                                        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !store.shownRequestable.isEmpty {
                            SectionLabel("Ask first")
                            CardList {
                                ForEach(Array(store.shownRequestable.enumerated()), id: \.element.id) { i, p in
                                    if i > 0 { RowDivider() }
                                    HStack(spacing: 12) {
                                        Avatar(url: p.avatarUrl, initials: p.avatarInitials ?? String((p.fullName ?? "?").prefix(1)), color: p.avatarColor, size: 40)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(language.language.isKurdish ? (p.fullNameKu ?? p.fullName ?? "") : (p.fullName ?? "")).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                            Text([p.grade, p.section].compactMap { $0 }.joined()).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                        }
                                        Spacer()
                                        if p.pending == true {
                                            Text("Asked").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                        } else {
                                            Button("Ask") { Task { await store.request(p.id) } }
                                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
                                        }
                                    }
                                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                                }
                            }
                            Text("They have to say yes before the room opens. Nobody can be messaged out of the blue.")
                                .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                        }

                        if store.shownContacts.isEmpty && store.shownRequestable.isEmpty && store.requests.isEmpty {
                            ContentUnavailableView("Nobody to message", systemImage: "person.crop.circle.badge.questionmark",
                                                   description: Text("Your class rooms are already in the list behind this. The school decides who you may message directly."))
                        }
                    }
                    if let error = store.error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                    Spacer(minLength: 40)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await store.load() }
        }
    }
}
