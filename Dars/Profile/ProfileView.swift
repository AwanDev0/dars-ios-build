import Foundation
import Observation
import SwiftUI
import Supabase

struct ProfileView: View {
    let profile: Profile
    @Environment(AuthStore.self) private var auth
    @Environment(LanguageStore.self) private var language
    @Environment(PaletteStore.self) private var palettes
    @Environment(SettingsStore.self) private var settings
    @State private var changingPassword = false
    @State private var joining = false
    @State private var school: School?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    header
                    group("Account") {
                        NavigationLink { EditProfileView(profile: profile) { Task { await auth.reload() } } } label: {
                            rowLabel("Edit profile", "person.crop.circle", value: nil)
                        }
                        Divider().padding(.leading, 54)
                        row("Change password", "key.fill") { changingPassword = true }
                    }
                    schoolSection
                    group("Look") {
                        NavigationLink { AppearanceView() } label: {
                            rowLabel("Appearance", "paintpalette.fill", value: palettes.current.name)
                        }
                        Divider().padding(.leading, 54)
                        NavigationLink { LanguageView() } label: {
                            rowLabel("Language", "globe", value: language.language.endonym)
                        }
                    }
                    group("Notifications") {
                        NavigationLink { NotificationsView(me: profile.id) } label: {
                            rowLabel("What Dars tells you about", "bell.badge.fill", value: nil)
                        }
                    }
                    group("Privacy") {
                        lockRow
                        Divider().padding(.leading, 54)
                        NavigationLink { PrivacyView(profile: profile) } label: {
                            rowLabel("Privacy & data", "hand.raised.fill", value: nil)
                        }
                    }
                    Button {
                        Task { await auth.signOut() }
                    } label: {
                        Text("common.signOut").darsType(.headline).foregroundStyle(DarsColor.danger)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Text("Dars · iOS").darsType(.caption).foregroundStyle(DarsColor.labelTertiary).frame(maxWidth: .infinity)
                    Spacer(minLength: 96)
                }
                .padding(Metrics.Space.md)
            }
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
            .sheet(isPresented: $joining) { JoinView(profile: profile) }
            .task {
                guard let id = profile.schoolId else { return }
                do {
                    let rows: [School] = try await SupabaseService.client.from("schools").select(School.columns).eq("id", value: id).execute().value
                    school = rows.first
                } catch {}
            }
        }
    }

    @ViewBuilder
    private var schoolSection: some View {
        switch profile.role {
        case .student:
            group("School") {
                NavigationLink { InsightsView(profile: profile) } label: {
                    rowLabel("Insights", "chart.xyaxis.line", value: nil)
                }
                Divider().padding(.leading, 54)
                NavigationLink { ExamsView(profile: profile) } label: {
                    rowLabel("Tests & exams", "doc.text.fill", value: nil)
                }
                Divider().padding(.leading, 54)
                NavigationLink { TeachersView(profile: profile) } label: {
                    rowLabel("My teachers", "person.badge.shield.checkmark", value: nil)
                }
                Divider().padding(.leading, 54)
                NavigationLink { StudentRecordView(student: profile, editable: false) } label: {
                    rowLabel("My record", "person.text.rectangle", value: nil)
                }
                Divider().padding(.leading, 54)
                row("Join a class", "qrcode.viewfinder") { joining = true }
            }
        case .parent:
            group("School") {
                row("Add a child", "figure.2.and.child.holdinghands") { joining = true }
            }
        case .teacher, .admin:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.md) {
            Avatar(url: profile.avatarURL, initials: profile.avatarInitials ?? String(profile.fullName.prefix(1)), color: profile.avatarColor, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName(kurdish: language.language.isKurdish)).darsType(.title2).foregroundStyle(DarsColor.labelPrimary)
                Text([roleName, profile.classLabel].compactMap { $0 }.joined(separator: " · ")).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary)
                if let school { Text(school.displayName(kurdish: language.language.isKurdish)).darsType(.footnote).foregroundStyle(DarsColor.labelTertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Metrics.Space.sm)
    }

    private var roleName: String {
        switch profile.role {
        case .student: return "Student"
        case .teacher: return "Teacher"
        case .parent: return "Parent"
        case .admin: return "Admin"
        }
    }

    private var lockRow: some View {
        let bio = SettingsStore.biometry
        return HStack(spacing: 14) {
            icon(bio.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text("App lock").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                Text(bio.available ? "\(bio.name) when Dars opens" : "Set a passcode on this phone first").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { settings.lockEnabled }, set: { on in
                Task {
                    if on, await SettingsStore.authenticate(reason: "Turn on the app lock") { settings.lockEnabled = true; HapticEngine.play(.success) }
                    else if !on { settings.lockEnabled = false }
                }
            }))
            .labelsHidden().tint(DarsColor.accent).disabled(!bio.available)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12)
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button { HapticEngine.play(.selection); action() } label: { rowLabel(title, symbol, value: nil) }.buttonStyle(.plain)
    }

    private func rowLabel(_ title: LocalizedStringKey, _ symbol: String, value: String?) -> some View {
        HStack(spacing: 14) {
            icon(symbol)
            Text(title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
            Spacer()
            if let value { Text(value).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
            .frame(width: 32, height: 32).background(DarsColor.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct Avatar: View {
    let url: String?
    let initials: String
    let color: String?
    var size: CGFloat = 40
    @State private var signed: URL?

    var body: some View {
        ZStack {
            Circle().fill(Color(hexString: color))
            if let signed {
                AsyncImage(url: signed) { $0.resizable().scaledToFill() } placeholder: { initialsText }
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            guard let url, !url.isEmpty else { signed = nil; return }
            signed = await SecureMedia.signed(url)
        }
    }

    private var initialsText: some View {
        Text(initials).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
    }
}

struct AppearanceView: View {
    @Environment(PaletteStore.self) private var palettes
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Light or dark").darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    Picker("Appearance", selection: Binding(get: { settings.mode }, set: { settings.mode = $0; HapticEngine.play(.selection) })) {
                        ForEach(AppearanceMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colours").darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    Text(palettes.current.note).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary).padding(.horizontal, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(DarsPalette.all) { p in swatch(p) }
                    }
                }
                Text("Gold is the brand and stays on the tab bar. Red, amber and green never change, so a warning always looks like one.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ p: DarsPalette) -> some View {
        let on = palettes.current == p
        let dark = scheme == .dark
        let bg = Color(hex: dark ? p.darkBg : p.lightBg)
        let card = Color(hex: dark ? p.darkCard : 0xFFFFFF)
        let accent = Color(hex: dark ? p.accentDark : p.accentLight)
        let action = Color(hex: dark ? p.actionDark : p.actionLight)
        return Button {
            HapticEngine.play(.impactLight)
            withAnimation(Motion.theme) { palettes.set(p) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(card).frame(height: 14)
                        HStack(spacing: 4) {
                            Capsule().fill(accent).frame(width: 26, height: 8)
                            Capsule().fill(action).frame(width: 16, height: 8)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DarsColor.separator, lineWidth: 0.5))
                HStack {
                    Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                    Spacer()
                    if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(DarsColor.accentLabel) }
                }
            }
            .padding(8)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? DarsColor.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct LanguageView: View {
    @Environment(LanguageStore.self) private var language

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { l in
                    Button {
                        HapticEngine.play(.selection)
                        withAnimation(Motion.theme) { language.set(l) }
                    } label: {
                        HStack {
                            Text(l.endonym).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                            Spacer()
                            if language.language == l { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(DarsColor.accentLabel) }
                        }
                        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if l != AppLanguage.allCases.last { Divider().padding(.leading, Metrics.Space.md) }
                }
            }
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(Metrics.Space.md)
            Text("Names, subjects and the school's own words come in the language the school entered them in.")
                .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, Metrics.Space.lg)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
@Observable
final class NotificationPrefsStore {
    var messages = true
    var assignments = true
    var grades = true
    var announcements = true
    private(set) var loaded = false
    private let client = SupabaseService.client

    struct Row: Codable {
        let user_id: UUID
        let messages: Bool
        let assignments: Bool
        let grades: Bool
        let announcements: Bool
    }

    func load(me: UUID) async {
        do {
            let rows: [Row] = try await client.from("notification_prefs").select("user_id, messages, assignments, grades, announcements").eq("user_id", value: me).execute().value
            if let r = rows.first {
                messages = r.messages; assignments = r.assignments; grades = r.grades; announcements = r.announcements
            }
        } catch {}
        loaded = true
    }

    func save(me: UUID) async {
        do {
            try await client.from("notification_prefs")
                .upsert(Row(user_id: me, messages: messages, assignments: assignments, grades: grades, announcements: announcements), onConflict: "user_id")
                .execute()
        } catch {}
    }
}

struct NotificationsView: View {
    let me: UUID
    @State private var store = NotificationPrefsStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                VStack(spacing: 0) {
                    toggle("Messages", "bubble.left.fill", "A new message in a room you are in", Binding(get: { store.messages }, set: { store.messages = $0 }))
                    Divider().padding(.leading, 60)
                    toggle("Homework & exams", "book.fill", "Something new set for your class", Binding(get: { store.assignments }, set: { store.assignments = $0 }))
                    Divider().padding(.leading, 60)
                    toggle("Marks", "chart.bar.fill", "A mark entered or changed", Binding(get: { store.grades }, set: { store.grades = $0 }))
                    Divider().padding(.leading, 60)
                    toggle("Announcements", "megaphone.fill", "From the school", Binding(get: { store.announcements }, set: { store.announcements = $0 }))
                }
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!store.loaded)
                Text("Turning one off here stops the push on every phone you are signed in on.")
                    .darsType(.caption).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(me: me) }
    }

    private func toggle(_ title: LocalizedStringKey, _ symbol: String, _ detail: LocalizedStringKey, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
                .frame(width: 32, height: 32).background(DarsColor.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                Text(detail).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { on.wrappedValue }, set: { v in
                on.wrappedValue = v
                HapticEngine.play(.selection)
                Task { await store.save(me: me) }
            }))
            .labelsHidden().tint(DarsColor.accent)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12)
    }
}

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var again = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                field("New password", $password)
                field("Again", $again)
                if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                Text("At least 6 characters. You stay signed in on this phone.").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                Spacer()
                DarsButton(title: "Change password", kind: .primary, systemImage: "checkmark", isLoading: working, fullWidth: true) { Task { await change() } }
                    .disabled(password.count < 6 || password != again)
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.backgroundBase.ignoresSafeArea())
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func field(_ title: LocalizedStringKey, _ text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textContentType(.newPassword)
            .padding(.horizontal, 14).frame(height: 52)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DarsColor.separator, lineWidth: 0.5))
    }

    private func change() async {
        working = true
        defer { working = false }
        do {
            _ = try await SupabaseService.auth.update(user: UserAttributes(password: password))
            HapticEngine.play(.success)
            dismiss()
        } catch {
            HapticEngine.play(.error)
            self.error = "Couldn't change it: \(error.localizedDescription)"
        }
    }
}

struct PrivacyView: View {
    let profile: Profile
    @Environment(AuthStore.self) private var auth
    @State private var confirming = false
    @State private var working = false
    @State private var blocked = false
    @State private var error: String?

    static let policy = URL(string: "https://awandev0.github.io/kurdedu/privacy.html")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who sees what").darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        line("person.2", "Your classmates see your name and avatar — never your marks, your contact details or your parent.")
                        line("graduationcap", "Your teachers see your marks and attendance for the subjects they teach you.")
                        line("figure.2.and.child.holdinghands", "Your parent sees your timetable, marks and attendance.")
                        line("building.2", "The school's admin sees the school's records. Nobody outside your school sees anything.")
                        line("lock", "Photos and voice messages are private to the room they were sent in.")
                    }
                    .padding(Metrics.Space.md)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                VStack(spacing: 0) {
                    Link(destination: Self.policy) {
                        HStack { Text("Privacy policy").darsType(.headline).foregroundStyle(DarsColor.labelPrimary); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary) }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 14)
                    }
                    Divider().padding(.leading, Metrics.Space.md)
                    NavigationLink { BlockedPeopleView() } label: {
                        HStack { Text("Blocked people").darsType(.headline).foregroundStyle(DarsColor.labelPrimary); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary) }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 14)
                    }
                }
                .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete account").darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary).padding(.horizontal, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your name comes off the school's records, your messages and files are deleted, and the account is gone. Marks and attendance stay with the school as anonymous records, as the law requires of a school.")
                            .darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                        if blocked {
                            Text("You are the school's only admin. Make someone else an admin first, then delete this account.").darsType(.footnote).foregroundStyle(DarsColor.warning)
                        }
                        if let error { Text(error).darsType(.footnote).foregroundStyle(DarsColor.danger) }
                        DarsButton(title: "Delete my account", kind: .destructive, systemImage: "trash", isLoading: working, fullWidth: true) { confirming = true }
                    }
                    .padding(Metrics.Space.md)
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Spacer(minLength: 96)
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Privacy & data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this account for good?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func line(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(DarsColor.accentLabel).frame(width: 22)
            Text(text).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
        }
    }

    private func deleteAccount() async {
        working = true
        error = nil
        blocked = false
        defer { working = false }
        let client = SupabaseService.client
        struct Name: Decodable { let name: String }
        do {
            var mine: [Name] = []
            do { mine = try await client.rpc("my_storage_objects").execute().value } catch {}
            if !mine.isEmpty { do { _ = try await client.storage.from("chat-media").remove(paths: mine.map { $0.name }) } catch {} }
            try await client.rpc("delete_my_account").execute()
            HapticEngine.play(.success)
            await auth.signOut()
        } catch {
            let text = String(describing: error)
            if text.contains("last_admin") { blocked = true } else { self.error = text }
            HapticEngine.play(.error)
        }
    }
}

struct BlockedPeopleView: View {
    @Environment(LanguageStore.self) private var language
    @State private var people: [RosterEntry] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if people.isEmpty {
                    ContentUnavailableView("Nobody blocked", systemImage: "hand.raised", description: Text("Block someone from their message thread. They stop reaching you; you stop seeing them."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(people) { p in
                            HStack(spacing: 12) {
                                Avatar(url: p.avatarUrl, initials: p.avatarInitials ?? String((p.fullName ?? "?").prefix(1)), color: p.avatarColor, size: 40)
                                Text(language.language.isKurdish ? (p.fullNameKu ?? p.fullName ?? "") : (p.fullName ?? "")).darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                                Spacer()
                                Button("Unblock") { Task { await unblock(p) } }.font(.system(size: 14, weight: .semibold)).foregroundStyle(DarsColor.accentLabel)
                            }
                            .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
                            if p.id != people.last?.id { Divider().padding(.leading, 68) }
                        }
                    }
                    .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(Metrics.Space.md)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let rows: [RosterEntry] = try await SupabaseService.client.rpc("blocked_people").execute().value
            people = rows
        } catch {}
        loading = false
    }

    private func unblock(_ p: RosterEntry) async {
        HapticEngine.play(.selection)
        withAnimation(Motion.arrive) { people.removeAll { $0.id == p.id } }
        do {
            try await SupabaseService.client.rpc("unblock_user", params: ["p_user": p.id.uuidString]).execute()
        } catch {
            await load()
        }
    }
}
