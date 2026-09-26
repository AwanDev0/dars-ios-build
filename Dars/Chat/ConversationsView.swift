import Foundation
import Observation
import SwiftUI
import Supabase

struct ConversationRow: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: String
    let title: String?
    let lastMessageAt: String?
    let lockedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case lastMessageAt = "last_message_at"
        case lockedAt = "locked_at"
    }
}

struct MemberRow: Codable, Sendable {
    let conversationId: UUID
    let userId: UUID
    let mutedAt: String?
    let lastReadAt: String?
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case mutedAt = "muted_at"
        case lastReadAt = "last_read_at"
    }
}

struct MessageRow: Codable, Identifiable, Hashable, Sendable {
    static let columns = "id, conversation_id, sender_id, body, kind, attachment_url, attachment_name, attachment_meta, reply_to_id, created_at, deleted, pinned, edited"
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let body: String?
    let kind: String
    let attachmentUrl: String?
    let attachmentName: String?
    let attachmentMeta: AttachmentMeta?
    let replyToId: UUID?
    let createdAt: String
    let deleted: Bool?
    let pinned: Bool?
    let edited: Bool?

    struct AttachmentMeta: Codable, Hashable, Sendable {
        let seconds: Double?
    }

    var voiceSeconds: Double? { attachmentMeta?.seconds }

    var preview: String {
        if deleted == true { return "Message removed" }
        switch kind {
        case "image": return "Photo"
        case "voice", "audio": return "Voice message"
        case "pdf", "file": return attachmentName ?? "Attachment"
        default: return body ?? ""
        }
    }
    var date: Date { ISO8601.parse(createdAt) }

    enum CodingKeys: String, CodingKey {
        case id, body, kind, deleted, pinned, edited
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case attachmentUrl = "attachment_url"
        case attachmentName = "attachment_name"
        case attachmentMeta = "attachment_meta"
        case replyToId = "reply_to_id"
        case createdAt = "created_at"
    }
}

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let plain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static func parse(_ s: String) -> Date {
        withFraction.date(from: s) ?? plain.date(from: s) ?? plain.date(from: s.replacingOccurrences(of: " ", with: "T") + "Z") ?? Date()
    }
}

struct ConversationItem: Identifiable, Hashable {
    let id: UUID
    let kind: String
    let title: String
    let initials: String
    let color: String?
    let preview: String
    let previewFrom: String?
    let at: Date?
    let unread: Bool
    let muted: Bool
    let locked: Bool
}

@MainActor
@Observable
final class ConversationsStore {
    private(set) var items: [ConversationItem] = []
    private(set) var loading = true
    private(set) var error: DarsError?
    var filter = "all"

    private let client = SupabaseService.client

    func load(me: UUID) async {
        error = nil
        do {
            let mine: [MemberRow] = try await client.from("conversation_members")
                .select("conversation_id, user_id, muted_at, last_read_at")
                .eq("user_id", value: me).is("left_at", value: nil).execute().value
            let ids = mine.map { $0.conversationId }
            guard !ids.isEmpty else { items = []; loading = false; return }
            let idList = ids.map { $0.uuidString }

            async let convs: [ConversationRow] = try await client.from("conversations").select("id, kind, title, last_message_at, locked_at")
                .in("id", values: idList).order("last_message_at", ascending: false).execute().value
            async let others: [MemberRow] = try await client.from("conversation_members").select("conversation_id, user_id, muted_at, last_read_at")
                .in("conversation_id", values: idList).neq("user_id", value: me).execute().value
            async let last: [MessageRow] = try await client.from("messages").select(MessageRow.columns)
                .in("conversation_id", values: idList).order("created_at", ascending: false).limit(300).execute().value

            let otherIds = Set(try await others.map { $0.userId })
            let people: [Profile] = otherIds.isEmpty ? [] : try await client.from("profiles").select(Profile.columns)
                .in("id", values: otherIds.map { $0.uuidString }).execute().value
            let byId = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
            let membersByConv = Dictionary(grouping: try await others, by: { $0.conversationId })
            let lastByConv = Dictionary(grouping: try await last, by: { $0.conversationId }).mapValues { $0.first }
            let myRows = Dictionary(uniqueKeysWithValues: mine.map { ($0.conversationId, $0) })

            items = try await convs.map { c in
                let other = membersByConv[c.id]?.first.flatMap { byId[$0.userId] }
                let title = c.kind == "dm" ? (other?.fullName ?? "Conversation") : (c.title ?? "Room")
                let msg = lastByConv[c.id] ?? nil
                let read = myRows[c.id]?.lastReadAt.map(ISO8601.parse) ?? .distantPast
                return ConversationItem(
                    id: c.id, kind: c.kind, title: title,
                    initials: c.kind == "dm" ? (other?.avatarInitials ?? String(title.prefix(1))) : String(title.prefix(3)),
                    color: c.kind == "dm" ? other?.avatarColor : nil,
                    preview: msg?.preview ?? "",
                    previewFrom: (msg != nil && c.kind != "dm") ? byId[msg!.senderId]?.fullName.split(separator: " ").first.map(String.init) : nil,
                    at: msg?.date ?? c.lastMessageAt.map(ISO8601.parse),
                    unread: (msg.map { $0.date > read && $0.senderId != me } ?? false),
                    muted: myRows[c.id]?.mutedAt != nil,
                    locked: c.lockedAt != nil
                )
            }
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    var shown: [ConversationItem] {
        switch filter {
        case "dm": return items.filter { $0.kind == "dm" }
        case "class": return items.filter { $0.kind != "dm" && !$0.locked }
        case "school": return items.filter { $0.locked }
        default: return items
        }
    }
    var unread: Int { items.filter { $0.unread }.count }
}

struct ConversationsView: View {
    let profile: Profile
    @Environment(PushRegistrar.self) private var push
    @State private var store = ConversationsStore()
    @State private var starting = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.md) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Messages").darsType(.largeTitle).foregroundStyle(DarsColor.labelPrimary)
                            Text(store.unread == 0 ? "All read" : "\(store.unread) unread").darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                        }
                        Spacer()
                        Button { HapticEngine.play(.selection); starting = true } label: {
                            Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(DarsColor.onAccent)
                                .frame(width: 36, height: 36).background(DarsColor.accent, in: Circle())
                        }
                        .accessibilityLabel("New message")
                    }
                    HStack(spacing: 8) {
                        chip("All", "all"); chip("Teachers", "dm"); chip("Classes", "class"); chip("School", "school")
                    }
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if store.shown.isEmpty {
                        ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.bubble.right", description: Text("Your class rooms appear here once the school sets them up."))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(store.shown) { item in
                                NavigationLink(value: item) { row(item) }
                                    .buttonStyle(.plain)
                                if item.id != store.shown.last?.id { Divider().padding(.leading, 74) }
                            }
                        }
                    }
                    if let error = store.error { error.messageText.darsType(.footnote).foregroundStyle(DarsColor.danger) }
                    Spacer(minLength: 96)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationDestination(for: ConversationItem.self) { item in
                ThreadView(conversation: item, me: profile)
            }
            .task { await store.load(me: profile.id) }
            .refreshable { await store.load(me: profile.id) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $starting) {
                NewChatView(me: profile) { conversation in
                    Task {
                        await store.load(me: profile.id)
                        if let item = store.items.first(where: { $0.id == conversation }) { path.append(item) }
                    }
                }
            }
            .onChange(of: push.pendingConversation) { _, id in
                guard let id else { return }
                Task {
                    if store.items.isEmpty { await store.load(me: profile.id) }
                    if let item = store.items.first(where: { $0.id == id }) { path.append(item) }
                    push.pendingConversation = nil
                }
            }
        }
    }

    private func chip(_ title: String, _ key: String) -> some View {
        let on = store.filter == key
        return Button {
            HapticEngine.play(.selection)
            withAnimation(Motion.selection) { store.filter = key }
        } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? DarsColor.onAccent : DarsColor.labelPrimary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(on ? DarsColor.accent : DarsColor.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: ConversationItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(item.kind == "dm" ? Color(hexString: item.color) : Color(hex: 0x5856D6).opacity(0.25)).frame(width: 48, height: 48)
                if item.kind == "dm" {
                    Text(item.initials).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                } else {
                    Image(systemName: item.locked ? "megaphone.fill" : "person.2.fill").foregroundStyle(Color(hex: 0x8B87F5))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                    if item.locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(DarsColor.labelTertiary) }
                    if item.muted { Image(systemName: "bell.slash.fill").font(.system(size: 10)).foregroundStyle(DarsColor.labelTertiary) }
                    Spacer()
                    if let at = item.at { Text(Self.when(at)).darsType(.footnote).foregroundStyle(DarsColor.labelTertiary) }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
                }
                Text((item.previewFrom.map { "\($0): " } ?? "") + item.preview).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary).lineLimit(2)
            }
            .overlay(alignment: .leading) {
                if item.unread { Circle().fill(DarsColor.accent).frame(width: 8, height: 8).offset(x: -70) }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    static func when(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}
