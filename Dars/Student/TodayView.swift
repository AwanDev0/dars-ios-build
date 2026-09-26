import SwiftUI

struct TodayView: View {
    let profile: Profile
    @Environment(LanguageStore.self) private var language
    @State private var store = TodayStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                header
                NotificationPrimer()
                nowCard
                section("Today's plan") {
                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if store.periods.isEmpty {
                        empty("Nothing on today.")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Metrics.Space.sm) {
                                ForEach(store.periods.filter { !$0.isBreak }) { p in
                                    periodCard(p, now: store.now?.id == p.id)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, Metrics.Space.md)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .padding(.horizontal, -Metrics.Space.md)
                    }
                }
                section("From school") {
                    if store.announcements.isEmpty && !store.loading {
                        empty("No announcements yet.")
                    } else {
                        DarsCard(radius: Metrics.Radius.lg) {
                            VStack(spacing: 0) {
                                ForEach(Array(store.announcements.enumerated()), id: \.element.id) { i, a in
                                    if i > 0 { Divider().padding(.leading, 62) }
                                    announcementRow(a)
                                }
                            }
                        }
                    }
                }
                if let error = store.error {
                    error.messageText
                        .darsType(.footnote)
                        .foregroundStyle(DarsColor.danger)
                }
                Spacer(minLength: 96)
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.top, Metrics.Space.xs)
        }
        .background(DarsColor.backgroundBase.ignoresSafeArea())
        .task { await store.load(for: profile) }
        .refreshable { await store.load(for: profile) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting + ", " + firstName)
                    .darsType(.largeTitle)
                    .foregroundStyle(DarsColor.labelPrimary)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .darsType(.subheadline)
                    .foregroundStyle(DarsColor.labelSecondary)
            }
            Spacer()
            ZStack {
                Circle().fill(Color(hexString: profile.avatarColor)).frame(width: 40, height: 40)
                Text(profile.avatarInitials ?? String(profile.fullName.prefix(1)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var firstName: String {
        let name = profile.displayName(kurdish: language.language.isKurdish)
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    @ViewBuilder
    private var nowCard: some View {
        if let now = store.now {
            HStack(spacing: Metrics.Space.sm) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SubjectColor.of(now.subject))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "book.fill").foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now" + (now.room.map { " · \($0)" } ?? "")).darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    Text(now.subject ?? "").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                    if let t = now.teacher, !t.isEmpty { Text(t).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("until").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    Text(String((now.endTime ?? "").prefix(5))).darsType(.headline).foregroundStyle(DarsColor.accentLabel).monospacedDigit()
                }
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous).strokeBorder(DarsColor.accent, lineWidth: 1.5))
        } else if !store.loading {
            HStack(spacing: Metrics.Space.sm) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DarsColor.surfaceGrouped)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "calendar").foregroundStyle(DarsColor.labelSecondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.periods.isEmpty ? "Free day" : "Between lessons").darsType(.caption).foregroundStyle(DarsColor.labelTertiary)
                    Text(store.periods.isEmpty ? "Nothing on the timetable today" : "The next lesson is on the way").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                }
                Spacer()
            }
            .padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
        }
    }

    private func periodCard(_ p: ScheduleItem, now: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SubjectColor.of(p.subject).opacity(0.22))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "book.fill").font(.system(size: 12)).foregroundStyle(SubjectColor.of(p.subject)))
                Text(String((p.startTime ?? "").prefix(5))).darsType(.footnote).foregroundStyle(now ? DarsColor.accentLabel : DarsColor.labelSecondary).monospacedDigit()
            }
            Text(p.subject ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
            Text([p.room, p.teacher].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 12.5)).foregroundStyle(DarsColor.labelSecondary).lineLimit(1)
        }
        .padding(Metrics.Space.sm)
        .frame(width: 140, alignment: .leading)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(now ? DarsColor.accent : .clear, lineWidth: 1.5))
    }

    private func announcementRow(_ a: Announcement) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xAF52DE).opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "megaphone.fill").font(.system(size: 14)).foregroundStyle(Color(hex: 0xAF52DE)))
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title ?? "From school").darsType(.headline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                if let b = a.body, !b.isEmpty {
                    Text(b).darsType(.footnote).foregroundStyle(DarsColor.labelSecondary).lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(Metrics.Space.md)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            Text(title)
                .darsType(.caption)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(DarsColor.labelTertiary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func empty(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .darsType(.subheadline)
            .foregroundStyle(DarsColor.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum SubjectColor {
    static func of(_ name: String?) -> Color {
        switch name {
        case "Mathematics", "Maths", "Math": return Color(hex: 0x5856D6)
        case "Physics": return Color(hex: 0xFF9500)
        case "Chemistry": return Color(hex: 0xFF3B30)
        case "English": return Color(hex: 0x34C759)
        case "Biology": return Color(hex: 0x007AFF)
        case "Kurdish": return Color(hex: 0x009688)
        case "Arabic": return Color(hex: 0xAF52DE)
        default: return Color(hex: 0x5856D6)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    init(hexString: String?) {
        guard let s = hexString?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), s.count == 6, let v = UInt32(s, radix: 16) else {
            self = Color(hex: 0xFAB900); return
        }
        self.init(hex: v)
    }
}
