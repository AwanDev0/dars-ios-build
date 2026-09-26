import SwiftUI

struct TodayView: View {
    let profile: Profile
    @Environment(LanguageStore.self) private var language
    @Environment(\.openTab) private var openTab
    @State private var store = StudentHomeStore()
    @State private var route: HomeRoute?
    @State private var clock = Date()

    enum HomeRoute: Hashable, Identifiable {
        case attendance
        var id: Self { self }
    }

    private var kurdish: Bool { language.language.isKurdish }

    var body: some View {
        NavigationStack {
            Group {
                if store.loading {
                    VStack(spacing: 12) {
                        DarsSkeleton(height: 104, corner: 20)
                        ForEach(1...3, id: \.self) { i in
                            DarsSkeleton(height: 62, corner: 16, delay: Double(i) * 0.09)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else if let error = store.error {
                    DarsErrorView(message: error, retry: LocalizedStringKey(L("common_retry_short"))) { reload() }
                } else if store.scheduleMissing && store.restOfDay.isEmpty && store.notices.isEmpty {
                    DarsEmpty(title: L("today_no_schedule"), body: L("today_no_schedule_body"), icon: "Filled.CalendarMonth")
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .darsGround()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { r in
                switch r {
                case .attendance: AttendanceCalendarView(student: profile)
                }
            }
        }
        .task { await store.load(profile, kurdish: kurdish) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                clock = Date()
            }
        }
    }

    private func reload() { Task { await store.load(profile, kurdish: kurdish) } }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HomeHeader(
                    greeting: store.birthday ? L("home_happy_birthday") : greeting,
                    name: firstName,
                    subline: subline,
                    initials: profile.avatarInitials ?? String(profile.fullName.prefix(1)),
                    avatarURL: profile.avatarURL,
                    avatarColor: profile.avatarColor,
                    ring: store.review.map { HomeAccent.review($0.tone) },
                    unreadMessages: store.unreadMessages,
                    onMessages: { openTab("messages") },
                    onNotifications: { openTab("messages") },
                    onProfile: { openTab("profile") }
                )
                studentHome
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load(profile, kurdish: kurdish) }
    }

    private var firstName: String {
        let full = profile.displayName(kurdish: kurdish)
        let first = full.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? L("tabs_profile") : first
    }

    private var subline: String {
        if store.phase == .tomorrow, let key = store.targetDayKey {
            return L("home_schools_out", DayName.full(key, kurdish: kurdish))
        }
        return DarsDate.todayLine(kurdish: kurdish)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return L(hour < 12 ? "home_good_morning" : (hour < 17 ? "home_good_afternoon" : "home_good_evening"))
    }

    @ViewBuilder
    private var nowSection: some View {
        let afternoon = store.phase == .tomorrow
        if afternoon {
            let lessons = store.restOfDay.filter { !$0.isBreak }
            NowCard(
                label: L("home_next_school_day"),
                headline: store.targetDayLabel ?? L("home_tomorrow"),
                detail: tomorrowLine(lessons),
                accent: lessons.isEmpty ? Tokens.textMuted : SubjectColor.of(lessons.first?.subject),
                icon: "Filled.WbTwilight",
                onClick: { openTab("schedule") }
            )
            .darsEnter()
        } else if !store.restOfDay.isEmpty {
            let now = nowDisplay()
            NowCard(label: now.label, headline: now.headline, detail: now.detail, accent: now.accent, progress: now.progress, onClick: { openTab("schedule") })
                .darsEnter()
        }
    }

    private func tomorrowLine(_ lessons: [DayItem]) -> String? {
        if let closed = store.closureReason { return L("home_no_school_tomorrow", closed) }
        if lessons.isEmpty { return L("schedule_free_day") }
        return tomorrowDetail(store.restOfDay)
    }

    @ViewBuilder
    private var studentHome: some View {
        let afternoon = store.phase == .tomorrow
        nowSection

        if let review = store.review {
            SectionHead(title: L("review_your_week"))
            ReviewStrip(review: review).darsEnter()
        }

        if store.restOfDay.contains(where: { !$0.isBreak }) {
            SectionHead(title: L(afternoon ? "home_tomorrows_plan" : "home_todays_plan"), action: LocalizedStringKey(L("common_view_all")), onAction: { openTab("schedule") })
            LessonStrip(items: store.restOfDay) { openTab("schedule") }
        }

        if !store.bag.isEmpty && (afternoon || store.phase == .morning) {
            SectionHead(title: L("bag_title"))
            BagCard(items: store.bag, ticked: store.bagTicked, packed: store.bagPacked) { store.tickBag($0) }
                .darsEnter()
        }

        if afternoon {
            tonightSection
        }

        if !store.week.isEmpty {
            SectionHead(title: L("home_this_week"), action: LocalizedStringKey(L("home_calendar")), onAction: { route = .attendance })
            WeekStrip(days: store.week, rate: store.weekRate, streak: store.streak) { route = .attendance }
                .darsEnter()
        }

        if !store.marks.isEmpty {
            SectionHead(title: L("home_latest_marks"), action: LocalizedStringKey(L("common_view_all")), onAction: { openTab("marks") })
            MarksStrip(marks: store.marks) { openTab("marks") }
        }

        if let code = store.familyCode {
            SectionHead(title: L("home_family"))
            FamilyCodeStrip(code: code).darsEnter()
        }

        noticesSection
    }

    @ViewBuilder
    private var tonightSection: some View {
        SectionHead(title: L("tonight_title"), count: store.tonight.filter { !$0.done }.count.nonZero, action: LocalizedStringKey(L("common_view_all")), onAction: { openTab("work") })
        if store.tonight.isEmpty {
            InlineEmpty(title: L("tonight_nothing"), text: L("tonight_nothing_body"))
        } else {
            TonightCard(items: store.tonight, onTick: { id in Task { await store.tickWork(id) } }, onOpen: { openTab("work") })
                .darsEnter()
        }
        if !store.changes.isEmpty {
            SectionHead(title: L("home_while_at_school"), count: store.changes.count)
            ChangesCard(items: store.changes) { change in
                switch change.kind {
                case .posted: openTab("work")
                case .marked: openTab("marks")
                case .announced: openTab("messages")
                }
            }
            .darsEnter()
        }
    }

    @ViewBuilder
    private var noticesSection: some View {
        if !store.notices.isEmpty {
            SectionHead(title: L("card_from_school"), action: LocalizedStringKey(L("common_view_all")), onAction: { openTab("messages") })
            GroupedCard {
                ForEach(Array(store.notices.enumerated()), id: \.element.id) { index, notice in
                    if index > 0 { GroupDivider() }
                    GlanceRow(
                        icon: noticeIcon(notice.kind),
                        tint: notice.urgent ? Tokens.danger : noticeTint(notice.kind),
                        title: notice.title,
                        meta: noticeMeta(notice),
                        grouped: true,
                        onClick: { openTab(notice.kind == .attendance ? "home" : "messages") }
                    )
                }
            }
            .darsEnter()
        }
    }

    private func noticeMeta(_ notice: HomeNotice) -> String {
        [notice.value, notice.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func noticeIcon(_ kind: HomeNotice.Kind) -> String {
        switch kind {
        case .announcement: return "Filled.Campaign"
        case .unread: return "AutoMirrored.Filled.Chat"
        case .attendance: return "Filled.EventAvailable"
        }
    }

    private func noticeTint(_ kind: HomeNotice.Kind) -> Color {
        switch kind {
        case .announcement: return HomeAccent.announced
        case .unread: return HomeAccent.unread
        case .attendance: return HomeAccent.attendance
        }
    }

    private func tomorrowDetail(_ day: [DayItem]) -> String? {
        let lessons = day.filter { !$0.isBreak }
        guard let first = lessons.first else { return nil }
        return P("tomorrow_lessons", lessons.count) + " · " + L("tomorrow_first_at", first.time, SubjectName.label(first.subject, kurdish: kurdish))
    }

    private struct NowDisplay {
        let label: String
        let headline: String
        let detail: String?
        let accent: Color
        let progress: Double?
    }

    private func nowDisplay() -> NowDisplay {
        let state = nowState(store.restOfDay, loading: store.loading, now: clock)
        switch state {
        case .inClass(let item, let progress, let left):
            let leftText = L("now_min_left", left)
            let place = [item.classLabel, item.room, item.teacher].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return NowDisplay(
                label: L("now_label_now"),
                headline: item.subject.isEmpty ? L("now_lesson") : SubjectName.label(item.subject, kurdish: kurdish),
                detail: place.isEmpty ? leftText : L("now_left_where", leftText, place),
                accent: SubjectColor.of(item.subject),
                progress: progress
            )
        case .next(let item, let minutes):
            let when = minutes < 60 ? L("now_n_min", minutes) : L("now_hours_minutes", minutes / 60, minutes % 60)
            let starts = L("now_starts_in", item.time, when)
            return NowDisplay(
                label: L("now_label_next"),
                headline: item.subject.isEmpty ? L("now_lesson") : SubjectName.label(item.subject, kurdish: kurdish),
                detail: item.classLabel.map { "\($0) · \(starts)" } ?? starts,
                accent: SubjectColor.of(item.subject),
                progress: nil
            )
        case .done:
            return NowDisplay(label: L("now_done_for_today"), headline: L("now_school_day_finished"), detail: nil, accent: Tokens.textMuted, progress: nil)
        case .free:
            return NowDisplay(label: L("now_no_classes_today"), headline: L("now_enjoy_the_day"), detail: nil, accent: Tokens.textMuted, progress: nil)
        case .loading:
            return NowDisplay(label: " ", headline: " ", detail: nil, accent: Tokens.textMuted, progress: nil)
        }
    }
}

extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
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
