import AVFoundation
import Foundation
import Observation
import SwiftUI
import Supabase

enum SecureMedia {
    private static let publicPrefix = "/storage/v1/object/public/chat-media/"
    private static let authedPrefix = "/storage/v1/object/authenticated/chat-media/"

    static func path(_ url: String) -> String? {
        for prefix in [publicPrefix, authedPrefix] {
            if let r = url.range(of: prefix) {
                return String(url[r.upperBound...]).components(separatedBy: "?").first
            }
        }
        return nil
    }

    static func signed(_ url: String) async -> URL? {
        guard let p = path(url) else { return URL(string: url) }
        do { return try await SupabaseService.client.storage.from("chat-media").createSignedURL(path: p, expiresIn: 600) } catch { return nil }
    }
}

@MainActor
@Observable
final class ThreadStore {
    private(set) var messages: [MessageRow] = []
    private(set) var people: [UUID: Profile] = [:]
    private(set) var members: [RoomMember] = []
    private(set) var loading = true
    private(set) var sending = false
    private(set) var uploading = false
    private(set) var muted = false
    private(set) var error: DarsError?
    var draft = ""
    private(set) var signedURLs: [UUID: URL] = [:]

    private let client = SupabaseService.client
    private var channel: RealtimeChannelV2?
    private var listener: Task<Void, Never>?

    struct RoomMember: Codable, Identifiable, Sendable {
        let id: UUID
        let fullName: String?
        let fullNameKu: String?
        let role: String?
        let avatarInitials: String?
        let avatarColor: String?
        let avatarUrl: String?
        let isModerator: Bool?
        enum CodingKeys: String, CodingKey {
            case id, role
            case fullName = "full_name"; case fullNameKu = "full_name_ku"
            case avatarInitials = "avatar_initials"; case avatarColor = "avatar_color"; case avatarUrl = "avatar_url"
            case isModerator = "is_moderator"
        }
    }

    func open(_ conversation: UUID, me: UUID) async {
        error = nil
        do {
            async let rows: [MessageRow] = try await client.from("messages").select(MessageRow.columns)
                .eq("conversation_id", value: conversation).order("created_at", ascending: true).limit(300).execute().value
            async let mine: [MemberRow] = try await client.from("conversation_members").select("conversation_id, user_id, muted_at, last_read_at")
                .eq("conversation_id", value: conversation).execute().value
            let seats = try await mine
            let profiles = try await DarsData.profiles(ids: seats.map { $0.userId })
            people = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            muted = seats.first { $0.userId == me }?.mutedAt != nil
            messages = try await rows
            members = (try? await client.rpc("list_room_members", params: ["p_conv": conversation.uuidString]).execute().value) ?? []
            await markRead(conversation, me: me)
            listen(conversation, me: me)
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut {
            error = .network
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    private func listen(_ conversation: UUID, me: UUID) {
        let channel = client.channel("thread:\(conversation.uuidString)")
        let filter = "conversation_id=eq.\(conversation.uuidString)"
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages", filter: filter)
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "messages", filter: filter)
        self.channel = channel
        listener = Task { [weak self] in
            await channel.subscribe()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await insert in inserts {
                        guard let self, !Task.isCancelled else { return }
                        guard let row = try? insert.decodeRecord(as: MessageRow.self, decoder: JSONDecoder()) else { continue }
                        await MainActor.run {
                            guard !self.messages.contains(where: { $0.id == row.id }) else { return }
                            withAnimation(Motion.arrive) { self.messages.append(row) }
                            if row.senderId != me { HapticEngine.play(.selection) }
                        }
                        await self.markRead(conversation, me: me)
                    }
                }
                group.addTask {
                    for await update in updates {
                        guard let self, !Task.isCancelled else { return }
                        guard let row = try? update.decodeRecord(as: MessageRow.self, decoder: JSONDecoder()) else { continue }
                        await MainActor.run {
                            if let i = self.messages.firstIndex(where: { $0.id == row.id }) {
                                withAnimation(Motion.selection) { self.messages[i] = row }
                            }
                        }
                    }
                }
            }
        }
    }

    func close() {
        listener?.cancel()
        listener = nil
        if let channel {
            Task { await SupabaseService.client.removeChannel(channel) }
        }
        channel = nil
    }

    struct NewMessage: Encodable {
        let id: UUID
        let conversation_id: UUID
        let sender_id: UUID
        let body: String?
        let kind: String
        let attachment_url: String?
        let attachment_name: String?
        let attachment_meta: Meta?
        let reply_to_id: UUID?
        struct Meta: Encodable { let seconds: Double? }
    }

    func send(to conversation: UUID, me: UUID, replyTo: UUID? = nil) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        draft = ""
        await insert(NewMessage(id: UUID(), conversation_id: conversation, sender_id: me, body: text, kind: "text",
                                attachment_url: nil, attachment_name: nil, attachment_meta: nil, reply_to_id: replyTo))
    }

    func sendPhoto(_ data: Foundation.Data, to conversation: UUID, me: UUID, replyTo: UUID? = nil) async {
        uploading = true
        defer { uploading = false }
        do {
            let url = try await MediaUpload.chat(data, conversation: conversation, ext: "jpg", contentType: "image/jpeg")
            await insert(NewMessage(id: UUID(), conversation_id: conversation, sender_id: me, body: nil, kind: "image",
                                    attachment_url: url, attachment_name: nil, attachment_meta: nil, reply_to_id: replyTo))
        } catch {
            self.error = .server(String(describing: error))
            HapticEngine.play(.error)
        }
    }

    func sendVoice(_ data: Foundation.Data, seconds: Double, to conversation: UUID, me: UUID, replyTo: UUID? = nil) async {
        uploading = true
        defer { uploading = false }
        do {
            let url = try await MediaUpload.chat(data, conversation: conversation, ext: "m4a", contentType: "audio/mp4")
            await insert(NewMessage(id: UUID(), conversation_id: conversation, sender_id: me, body: nil, kind: "voice",
                                    attachment_url: url, attachment_name: nil, attachment_meta: .init(seconds: (seconds * 10).rounded() / 10), reply_to_id: replyTo))
        } catch {
            self.error = .server(String(describing: error))
            HapticEngine.play(.error)
        }
    }

    private func insert(_ row: NewMessage) async {
        do {
            let created: [MessageRow] = try await client.from("messages").insert(row).select(MessageRow.columns).execute().value
            HapticEngine.play(.success)
            if let made = created.first, !messages.contains(where: { $0.id == made.id }) {
                withAnimation(Motion.arrive) { messages.append(made) }
            }
            struct Push: Encodable, Sendable { let kind = "message"; let message_id: UUID }
            DarsData.knock(Push(message_id: row.id))
        } catch {
            self.error = .server(String(describing: error))
            HapticEngine.play(.error)
        }
    }

    struct SoftDelete: Encodable { let deleted: Bool; let body: String }
    struct Pin: Encodable { let pinned: Bool }
    struct Edit: Encodable { let body: String; let edited: Bool }

    func delete(_ m: MessageRow) async {
        do {
            try await client.from("messages").update(SoftDelete(deleted: true, body: "")).eq("id", value: m.id).execute()
            HapticEngine.play(.success)
        } catch { self.error = .server(String(describing: error)) }
    }

    func setPinned(_ m: MessageRow, _ on: Bool) async {
        do {
            try await client.from("messages").update(Pin(pinned: on)).eq("id", value: m.id).execute()
            HapticEngine.play(.selection)
        } catch { self.error = .server(String(describing: error)) }
    }

    func edit(_ m: MessageRow, to text: String) async {
        do {
            try await client.from("messages").update(Edit(body: text, edited: true)).eq("id", value: m.id).execute()
            HapticEngine.play(.success)
        } catch { self.error = .server(String(describing: error)) }
    }

    func setMuted(_ conversation: UUID, _ on: Bool) async {
        struct Args: Encodable { let p_conv: UUID; let p_muted: Bool }
        do {
            try await client.rpc("set_conversation_muted", params: Args(p_conv: conversation, p_muted: on)).execute()
            muted = on
            HapticEngine.play(.selection)
        } catch { self.error = .server(String(describing: error)) }
    }

    func leave(_ conversation: UUID) async {
        do { try await client.rpc("leave_conversation", params: ["p_conv": conversation.uuidString]).execute() }
        catch { self.error = .server(String(describing: error)) }
    }

    func block(_ user: UUID) async {
        do {
            try await client.rpc("block_user", params: ["p_user": user.uuidString]).execute()
            HapticEngine.play(.success)
        } catch { self.error = .server(String(describing: error)) }
    }

    struct ReportArgs: Encodable { let p_target: UUID; let p_reason: String; let p_note: String?; let p_anonymous: Bool }

    func report(person: UUID, reason: String, note: String?) async {
        do {
            try await client.rpc("report_person", params: ReportArgs(p_target: person, p_reason: reason, p_note: note, p_anonymous: false)).execute()
            HapticEngine.play(.success)
        } catch { self.error = .server(String(describing: error)) }
    }

    struct ReportMessage: Encodable { let message_id: UUID; let reporter_id: UUID; let reason: String; let note: String? }

    func report(message: MessageRow, me: UUID, reason: String, note: String?) async {
        do {
            try await client.from("message_reports").insert(ReportMessage(message_id: message.id, reporter_id: me, reason: reason, note: note)).execute()
            HapticEngine.play(.success)
        } catch { self.error = .server(String(describing: error)) }
    }

    private func markRead(_ conversation: UUID, me: UUID) async {
        struct Patch: Encodable { let last_read_at: String }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            try await client.from("conversation_members").update(Patch(last_read_at: iso.string(from: Date())))
                .eq("conversation_id", value: conversation).eq("user_id", value: me).execute()
        } catch {}
    }

    func signedURL(for message: MessageRow) async -> URL? {
        if let u = signedURLs[message.id] { return u }
        guard let raw = message.attachmentUrl, let u = await SecureMedia.signed(raw) else { return nil }
        signedURLs[message.id] = u
        return u
    }

    func name(_ id: UUID, kurdish: Bool) -> String { people[id]?.displayName(kurdish: kurdish) ?? "…" }
    func message(_ id: UUID?) -> MessageRow? { id.flatMap { i in messages.first { $0.id == i } } }
    var pinned: MessageRow? { messages.last { $0.pinned == true && $0.deleted != true } }
}

struct ThreadView: View {
    let conversation: ConversationItem
    let me: Profile
    @Environment(LanguageStore.self) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var store = ThreadStore()
    @State private var replyingTo: MessageRow?
    @State private var editing: MessageRow?
    @State private var reporting: MessageRow?
    @State private var showingInfo = false
    @State private var confirmLeave = false

    var body: some View {
        VStack(spacing: 0) {
            if let p = store.pinned { pinnedBar(p) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if store.loading { ProgressView().padding(.top, 40) }
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { i, m in
                            let prev = i > 0 ? store.messages[i - 1] : nil
                            if prev == nil || !Calendar.current.isDate(prev!.date, inSameDayAs: m.date) {
                                Text(dayLabel(m.date)).darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.vertical, 10)
                            }
                            bubble(m, showName: conversation.kind != "dm" && m.senderId != me.id && prev?.senderId != m.senderId)
                                .id(m.id)
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, Metrics.Space.md)
                    .padding(.top, Metrics.Space.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.messages.count) { withAnimation(Motion.arrive) { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.loading) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if store.uploading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Sending…").darsType(.caption).foregroundStyle(DarsColor.labelTertiary) }
                    .frame(maxWidth: .infinity).padding(.vertical, 6).background(DarsColor.surface)
            }
            if conversation.locked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Only the school posts here.")
                }
                .darsType(.footnote).foregroundStyle(DarsColor.labelTertiary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(DarsColor.surface)
            } else {
                Composer(conversation: conversation.id, me: me, store: store, replyingTo: $replyingTo)
            }
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showingInfo = true } label: {
                    VStack(spacing: 0) {
                        Text(conversation.title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                        Text(conversation.kind == "dm" ? "Tap for options" : "\(store.members.count) members").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(store.muted ? "Unmute" : "Mute", systemImage: store.muted ? "bell" : "bell.slash") {
                        Task { await store.setMuted(conversation.id, !store.muted) }
                    }
                    Button("Members", systemImage: "person.2") { showingInfo = true }
                    if conversation.kind != "dm" {
                        Button("Leave the room", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await store.open(conversation.id, me: me.id) }
        .onDisappear { store.close() }
        .sheet(isPresented: $showingInfo) {
            ThreadInfoSheet(conversation: conversation, store: store, me: me)
        }
        .sheet(item: $editing) { m in
            EditMessageSheet(text: m.body ?? "") { Task { await store.edit(m, to: $0) } }
        }
        .sheet(item: $reporting) { m in
            ReportSheet(what: "message") { reason, note in Task { await store.report(message: m, me: me.id, reason: reason, note: note) } }
        }
        .confirmationDialog("Leave this room?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await store.leave(conversation.id); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You stop getting its messages. The school can put you back in it.")
        }
    }

    private func pinnedBar(_ m: MessageRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(DarsColor.accentLabel)
            Text(m.preview).darsType(.caption).foregroundStyle(DarsColor.labelSecondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 7)
        .background(DarsColor.accentSoft)
    }

    @ViewBuilder
    private func bubble(_ m: MessageRow, showName: Bool) -> some View {
        let mine = m.senderId == me.id
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if showName {
                Text(store.name(m.senderId, kurdish: language.language.isKurdish)).darsType(.caption).fontWeight(.semibold)
                    .foregroundStyle(DarsColor.accentLabel).padding(.horizontal, 6)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if mine { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 4) {
                    if let parent = store.message(m.replyToId) { quoted(parent, mine: mine) }
                    content(m, mine: mine)
                }
                .padding(.horizontal, m.kind == "image" ? 0 : 13).padding(.vertical, m.kind == "image" ? 0 : 9)
                .background(mine ? DarsColor.accent : DarsColor.surface, in: BubbleShape(mine: mine))
                .clipShape(BubbleShape(mine: mine))
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 3) {
                        if m.edited == true { Text("edited").font(.system(size: 9.5)) }
                        Text(m.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 10.5)).monospacedDigit()
                    }
                    .foregroundStyle(mine ? DarsColor.onAccent.opacity(0.6) : DarsColor.labelTertiary)
                    .padding(6)
                    .opacity(m.kind == "image" ? 0 : 1)
                }
                .contextMenu { menu(m, mine: mine) }
                if !mine { Spacer(minLength: 48) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func menu(_ m: MessageRow, mine: Bool) -> some View {
        if m.deleted != true {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { withAnimation(Motion.selection) { replyingTo = m } }
            if m.kind == "text", let body = m.body, !body.isEmpty {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = body }
            }
            Button(m.pinned == true ? "Unpin" : "Pin", systemImage: m.pinned == true ? "pin.slash" : "pin") {
                Task { await store.setPinned(m, !(m.pinned ?? false)) }
            }
            if mine, m.kind == "text" {
                Button("Edit", systemImage: "pencil") { editing = m }
            }
            if mine {
                Button("Delete", systemImage: "trash", role: .destructive) { Task { await store.delete(m) } }
            } else {
                Button("Report", systemImage: "flag", role: .destructive) { reporting = m }
            }
        }
    }

    private func quoted(_ parent: MessageRow, mine: Bool) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(mine ? DarsColor.onAccent.opacity(0.5) : DarsColor.accent).frame(width: 2.5).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(store.name(parent.senderId, kurdish: language.language.isKurdish))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(mine ? DarsColor.onAccent.opacity(0.75) : DarsColor.accentLabel)
                Text(parent.preview).font(.system(size: 12))
                    .foregroundStyle(mine ? DarsColor.onAccent.opacity(0.7) : DarsColor.labelSecondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func content(_ m: MessageRow, mine: Bool) -> some View {
        let ink = mine ? DarsColor.onAccent : DarsColor.labelPrimary
        if m.deleted == true {
            Text("Message removed").italic().darsType(.subheadline).foregroundStyle(ink.opacity(0.6)).padding(.trailing, 44)
        } else {
            switch m.kind {
            case "image":
                SignedImage(message: m, store: store)
            case "voice", "audio":
                VoiceRow(message: m, store: store, ink: ink).padding(.trailing, 44)
            case "pdf", "file":
                FileRow(message: m, store: store, ink: ink).padding(.trailing, 44)
            default:
                Text(m.body ?? "").darsType(.body).foregroundStyle(ink).padding(.trailing, 52)
                    .textSelection(.enabled)
            }
        }
    }

    private func dayLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct BubbleShape: Shape {
    let mine: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18, tail: CGFloat = 6
        return UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: r, bottomLeading: mine ? r : tail, bottomTrailing: mine ? tail : r, topTrailing: r),
            style: .continuous
        ).path(in: rect)
    }
}

struct SignedImage: View {
    let message: MessageRow
    let store: ThreadStore
    @State private var url: URL?
    @State private var full = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").foregroundStyle(DarsColor.labelTertiary)
                    default: Skeleton(width: 220, height: 220, radius: 0)
                    }
                }
            } else {
                Skeleton(width: 220, height: 220, radius: 0)
            }
        }
        .frame(width: 220, height: 220)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if url != nil { full = true } }
        .task { url = await store.signedURL(for: message) }
        .fullScreenCover(isPresented: $full) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let url { AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) } }
                Button { full = false } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36).background(.white.opacity(0.18), in: Circle())
                }
                .padding()
            }
        }
    }
}

@MainActor
final class VoicePlayer: ObservableObject {
    @Published var playing = false
    private var player: AVPlayer?
    private var ended: Any?

    func toggle(_ url: URL) {
        if playing { player?.pause(); playing = false; return }
        if player == nil || (player?.currentItem?.asset as? AVURLAsset)?.url != url {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.playing = false; self?.player?.seek(to: .zero) }
            }
        }
        player?.play()
        playing = true
    }
}

struct VoiceRow: View {
    let message: MessageRow
    let store: ThreadStore
    let ink: Color
    @StateObject private var player = VoicePlayer()
    @State private var url: URL?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let url { HapticEngine.play(.selection); player.toggle(url) }
            } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ink).frame(width: 32, height: 32).background(ink.opacity(0.12), in: Circle())
            }
            .disabled(url == nil)
            HStack(spacing: 2) {
                ForEach(0..<22, id: \.self) { i in
                    Capsule().fill(ink.opacity(0.55)).frame(width: 2.5, height: CGFloat(6 + (i * 7 % 13)))
                }
            }
            Text(message.voiceSeconds.map { Composer.clock($0) } ?? "Voice")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(ink.opacity(0.75))
        }
        .task { url = await store.signedURL(for: message) }
    }
}

struct FileRow: View {
    let message: MessageRow
    let store: ThreadStore
    let ink: Color
    @Environment(\.openURL) private var openURL
    @State private var url: URL?

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill").font(.system(size: 18)).foregroundStyle(ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.attachmentName ?? "File").darsType(.subheadline).fontWeight(.semibold).foregroundStyle(ink).lineLimit(1)
                    Text("Tap to open").darsType(.caption).foregroundStyle(ink.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .task { url = await store.signedURL(for: message) }
    }
}

struct ThreadInfoSheet: View {
    let conversation: ConversationItem
    let store: ThreadStore
    let me: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var reportingPerson: ThreadStore.RoomMember?
    @State private var blocking: ThreadStore.RoomMember?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.md) {
                    Toggle(isOn: Binding(get: { store.muted }, set: { on in Task { await store.setMuted(conversation.id, on) } })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Mute this room").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                            Text("It still arrives; your phone stays quiet").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                        }
                    }
                    .tint(DarsColor.accent)
                    .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    SectionLabel("Members", trailing: "\(store.members.count)")
                    CardList {
                        ForEach(Array(store.members.enumerated()), id: \.element.id) { i, member in
                            if i > 0 { RowDivider() }
                            HStack(spacing: 12) {
                                Avatar(url: member.avatarUrl, initials: member.avatarInitials ?? String((member.fullName ?? "?").prefix(1)), color: member.avatarColor, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(language.language.isKurdish ? (member.fullNameKu ?? member.fullName ?? "") : (member.fullName ?? ""))
                                        .darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                    Text([member.role?.capitalized, member.isModerator == true ? "Moderator" : nil].compactMap { $0 }.joined(separator: " · "))
                                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                                }
                                Spacer()
                                if member.id != me.id {
                                    Menu {
                                        Button("Report", systemImage: "flag") { reportingPerson = member }
                                        Button("Block", systemImage: "hand.raised", role: .destructive) { blocking = member }
                                    } label: { Image(systemName: "ellipsis").foregroundStyle(DarsColor.labelTertiary).frame(width: 30, height: 30) }
                                }
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                        }
                    }
                    Text("Blocking stops their messages reaching you and yours reaching them. The school can still see the room.")
                        .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle(conversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $reportingPerson) { p in
                ReportSheet(what: "person") { reason, note in Task { await store.report(person: p.id, reason: reason, note: note) } }
            }
            .confirmationDialog("Block this person?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
                Button("Block", role: .destructive) { if let b = blocking { Task { await store.block(b.id) } }; blocking = nil; dismiss() }
                Button("Cancel", role: .cancel) { blocking = nil }
            }
        }
    }
}

struct EditMessageSheet: View {
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                TextField("Message", text: $text, axis: .vertical).lineLimit(3...8)
                    .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("It will be marked as edited. Nobody is told twice.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                Spacer()
                DarsButton(title: "Save", kind: .primary, systemImage: "checkmark", fullWidth: true) {
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct ReportSheet: View {
    let what: String
    let onSend: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "rude"
    @State private var note = ""

    private let reasons: [(String, LocalizedStringKey)] = [
        ("rude", "Rude or insulting"),
        ("bullying", "Bullying"),
        ("inappropriate", "Not for school"),
        ("cheating", "Cheating"),
        ("other", "Something else"),
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Text("The school's office reads this and decides. Your name is on it.")
                    .darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                CardList {
                    ForEach(Array(reasons.enumerated()), id: \.offset) { i, r in
                        if i > 0 { RowDivider(inset: Metrics.Space.md) }
                        Button { HapticEngine.play(.selection); reason = r.0 } label: {
                            HStack {
                                Text(r.1).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                Spacer()
                                if reason == r.0 { Image(systemName: "checkmark").foregroundStyle(DarsColor.accentLabel) }
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("Anything to add?", text: $note, axis: .vertical).lineLimit(2...4)
                    .padding(14).background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                DarsButton(title: "Send the report", kind: .destructive, systemImage: "flag.fill", fullWidth: true) {
                    onSend(reason, note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
                    dismiss()
                }
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle(what == "person" ? "Report a person" : "Report a message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
