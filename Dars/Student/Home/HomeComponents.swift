import SwiftUI
import CoreImage.CIFilterBuiltins

struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .darsMaterial(RR(16))
    }
}

struct GroupDivider: View {
    var body: some View {
        Rectangle().fill(Tokens.border).frame(height: 1).padding(.leading, 62)
    }
}

struct InlineEmpty: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tokens.text)
            Text(verbatim: text).font(.system(size: 12)).lineSpacing(5).foregroundStyle(Tokens.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Tokens.well, in: RR(16))
    }
}

struct TickCircle: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().fill(on ? Tokens.accent : Color.clear)
            if !on { Circle().strokeBorder(Tokens.textFaint, lineWidth: 1.5) }
            if on { MaterialIcon("Filled.Check", size: 16).foregroundStyle(Tokens.onAccent) }
        }
        .frame(width: 26, height: 26)
        .animation(Motion.standard, value: on)
    }
}

struct HomeHeader: View {
    let greeting: String
    let name: String
    let subline: String
    let initials: String
    var avatarURL: String?
    var avatarColor: String?
    var ring: Color?
    var nameAccented = false
    var unreadMessages = 0
    var onMessages: (() -> Void)?
    let onNotifications: () -> Void
    let onProfile: () -> Void


    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: L("index_greet_name", greeting, name))
                    .font(.system(size: 22, weight: .bold))
                    .darsTracking(-0.6)
                    .foregroundStyle(nameAccented ? Tokens.accentText : Tokens.text)
                    .lineLimit(2)
                    .minimumScaleFactor(17.0 / 22.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !subline.isEmpty {
                    Text(verbatim: subline)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(2)
                }
            }
            if let onMessages {
                MotionIconButton(label: LocalizedStringKey(L("tabs_chat")), action: onMessages) {
                    MaterialIcon("Outlined.ChatBubbleOutline", size: 24).foregroundStyle(Tokens.text)
                }
                .overlay(alignment: .topTrailing) {
                    if unreadMessages > 0 {
                        Text(verbatim: unreadMessages > 9 ? "9+" : "\(unreadMessages)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Tokens.danger, in: Capsule())
                            .overlay(Capsule().strokeBorder(Tokens.bg, lineWidth: 1.5))
                            .offset(x: -4, y: 6)
                    }
                }
            }
            MotionIconButton(label: LocalizedStringKey(L("common_announcements")), action: onNotifications) {
                MaterialIcon("Outlined.Notifications", size: 24).foregroundStyle(Tokens.text)
            }
            Button {
                HapticEngine.play(.selection)
                onProfile()
            } label: {
                ZStack {
                    if let ring {
                        Circle().strokeBorder(ring, lineWidth: 2.5)
                        PersonAvatar(initials: String(initials.prefix(2)).uppercased(), url: avatarURL, colour: Color(hexString: avatarColor), size: 34)
                    } else {
                        PersonAvatar(initials: String(initials.prefix(2)).uppercased(), url: avatarURL, colour: Color(hexString: avatarColor), size: 40)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Circle())
            }
            .buttonStyle(DarsPress(scale: Motion.Scale.row, radius: 20))
            .padding(.leading, 4)
            .accessibilityLabel(Text(verbatim: name))
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

struct NowCard: View {
    let label: String
    let headline: String
    let detail: String?
    let accent: Color
    var icon = "Filled.CalendarMonth"
    var progress: Double?
    var onClick: (() -> Void)?
    @State private var fill: Double = 0

    var body: some View {
        let card = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(colors: [accent.opacity(0.16), accent.opacity(0.04), .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.95, y: 1.4))
            }
            .darsMaterial(RR(20))
        Group {
            if let onClick {
                Button {
                    HapticEngine.play(.selection)
                    onClick()
                } label: { card }
                .buttonStyle(DarsPress(scale: Motion.Scale.row, radius: 20))
            } else {
                card
            }
        }
        .onAppear { fill = min(max(progress ?? 0, 0), 1) }
        .onChange(of: progress) { _, p in withAnimation(Motion.arrive) { fill = min(max(p ?? 0, 0), 1) } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label).font(.system(size: 12, weight: .medium)).foregroundStyle(Tokens.textMuted).lineLimit(1)
            HStack(spacing: 12) {
                MaterialIcon(icon, size: 21)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .glassTile(accent, shape: RR(12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: headline).font(.system(size: 17, weight: .semibold)).darsTracking(-0.3).foregroundStyle(Tokens.text).lineLimit(1)
                    if let detail {
                        Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(Tokens.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            if progress != nil {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RR(2).fill(Tokens.border)
                        RR(2).fill(accent).frame(width: g.size.width * fill)
                    }
                }
                .frame(height: 3)
                .padding(.top, 14)
            }
        }
        .padding(16)
    }
}

struct GlanceRow: View {
    let icon: String?
    let tint: Color
    let title: String
    let meta: String
    var trailing: String?
    var grouped = false
    var onClick: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: 13) {
            if let icon {
                MaterialIcon(icon, size: 19)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .glassTile(tint, shape: RR(10))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                Text(verbatim: meta).font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(verbatim: trailing).font(.system(size: 11.5)).foregroundStyle(Tokens.textMuted).lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        Group {
            if let onClick {
                Button {
                    HapticEngine.play(.selection)
                    onClick()
                } label: {
                    if grouped { row } else { row.darsMaterial(RR(16)) }
                }
                .buttonStyle(DarsPress(scale: Motion.Scale.row, radius: grouped ? 0 : 16))
            } else {
                if grouped { row } else { row.darsMaterial(RR(16)) }
            }
        }
    }
}

struct DayRow: View {
    let item: DayItem
    var showTimeColumn = true
    @Environment(LanguageStore.self) private var language

    var body: some View {
        let fade: Double = item.past ? 0.45 : 1
        let accent = item.isBreak ? Tokens.textMuted : SubjectColor.of(item.subject)
        let kurdish = language.language.isKurdish
        HStack(spacing: 11) {
            if showTimeColumn {
                Text(verbatim: item.time).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Tokens.textMuted.opacity(fade)).frame(width: 38, alignment: .leading)
            }
            MaterialIcon(item.isBreak ? "Filled.Coffee" : SubjectIcon.of(item.subject), size: 17)
                .foregroundStyle(accent.opacity(fade))
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.16 * fade), in: RR(10))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: SubjectName.label(item.subject, kurdish: kurdish))
                    .font(.system(size: 14, weight: item.isBreak ? .regular : .semibold))
                    .foregroundStyle((item.isBreak || item.free ? Tokens.textMuted : Tokens.text).opacity(fade))
                    .lineLimit(1)
                if item.away {
                    Text(verbatim: item.cover.map { L("away_covered_by", $0) } ?? L("away_free_period"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle((item.cover != nil ? Tokens.accentText : Tokens.warning).opacity(fade))
                        .lineLimit(1)
                }
                let meta = showTimeColumn ? "" : [item.time.isEmpty ? nil : item.time, item.classLabel, item.room].compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(verbatim: meta).font(.system(size: 11.5)).foregroundStyle(Tokens.textMuted.opacity(fade)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            let trailing = [item.classLabel, item.room].compactMap { $0 }.joined(separator: " · ")
            if showTimeColumn && !trailing.isEmpty {
                Text(verbatim: trailing).font(.system(size: 11)).foregroundStyle(Tokens.textMuted.opacity(fade)).lineLimit(1)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}

struct LessonStrip: View {
    let items: [DayItem]
    let onOpen: () -> Void

    var body: some View {
        let lessons = items.filter { !$0.isBreak }
        let now = lessons.firstIndex { !$0.past }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    LessonTile(lesson: lesson, current: index == now, onClick: onOpen)
                        .darsStagger(index, step: 0.05, delay: 0.08, rise: 6)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }
}

private struct LessonTile: View {
    let lesson: DayItem
    let current: Bool
    let onClick: () -> Void
    @Environment(LanguageStore.self) private var language

    var body: some View {
        let colour = lesson.free ? Tokens.textMuted : SubjectColor.of(lesson.subject)
        let dim: Double = lesson.past ? 0.55 : 1
        let kurdish = language.language.isKurdish
        MotionCard(action: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    MaterialIcon(SubjectIcon.of(lesson.subject), size: 15)
                        .foregroundStyle(colour)
                        .frame(width: 28, height: 28)
                        .glassTile(colour, shape: RR(8))
                    Text(verbatim: lesson.time)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(current ? colour : Tokens.textMuted)
                }
                Text(verbatim: SubjectName.label(lesson.subject, kurdish: kurdish))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.text.opacity(dim))
                    .lineLimit(1)
                    .padding(.top, 10)
                Text(verbatim: lesson.free ? L("away_free_period") : (lesson.cover.map { L("away_covered_by", $0) } ?? (lesson.room ?? lesson.teacher ?? "")))
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textMuted.opacity(dim))
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(12)
            .animation(Motion.standard, value: lesson.past)
        }
        .frame(width: 132)
        .overlay { if current { RR(16).strokeBorder(colour.opacity(0.7), lineWidth: 1.5) } }
    }
}

struct BagCard: View {
    let items: [BagItem]
    let ticked: Set<String>
    let packed: Bool
    let onTick: (String) -> Void
    @Environment(LanguageStore.self) private var language
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var pulse: CGFloat = 1

    var body: some View {
        let tint = packed ? Tokens.success : Tokens.accent
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MaterialIcon("Filled.Backpack", size: 20)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .glassTile(tint, shape: RR(12))
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .leading) {
                        Text(verbatim: L(packed ? "bag_packed" : "bag_title"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(packed ? Tokens.success : Tokens.text)
                            .id(packed)
                            .transition(.opacity)
                    }
                    .animation(Motion.emphasis, value: packed)
                    Text(verbatim: L("bag_progress", items.filter { ticked.contains($0.id) }.count, items.count))
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            ForEach(items) { item in
                let on = ticked.contains(item.id)
                let colour = item.subject.map { SubjectColor.of($0) } ?? Tokens.accent
                MotionRow(action: { onTick(item.id) }) {
                    HStack(spacing: 12) {
                        TickCircle(on: on)
                        MaterialIcon(icon(item), size: 17)
                            .foregroundStyle(colour)
                            .frame(width: 34, height: 34)
                            .glassTile(colour, shape: RR(10))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: title(item))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(on ? Tokens.textMuted : Tokens.text)
                                .lineLimit(2)
                            if let detail = detail(item) {
                                Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(Tokens.textMuted).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            Spacer().frame(height: 6)
        }
        .darsMaterial(RR(16))
        .scaleEffect(pulse)
        .onChange(of: packed) { _, now in
            guard now else { return }
            HapticEngine.play(.success)
            guard !reduce else { return }
            withAnimation(Motion.press, completionCriteria: .logicallyComplete) { pulse = 1.02 } completion: {
                withAnimation(Motion.arrive) { pulse = 1 }
            }
        }
    }

    private func title(_ item: BagItem) -> String {
        switch item.kind {
        case .books: return L("bag_books")
        case .kit: return item.id == "kit:art" ? L("bag_art_kit") : L("bag_pe_kit")
        case .handIn: return L("bag_hand_in", item.title)
        case .exam: return L("bag_exam", item.title)
        }
    }

    private func detail(_ item: BagItem) -> String? {
        let kurdish = language.language.isKurdish
        switch item.kind {
        case .books:
            return item.detail?.split(separator: Character(BagRules.separator)).map { SubjectName.label(String($0), kurdish: kurdish) }.joined(separator: " · ")
        case .kit, .handIn:
            return item.subject.map { SubjectName.label($0, kurdish: kurdish) }
        case .exam:
            return L("bag_exam_kit")
        }
    }

    private func icon(_ item: BagItem) -> String {
        switch item.kind {
        case .books: return "AutoMirrored.Filled.MenuBook"
        case .kit: return item.id == "kit:art" ? "Filled.Brush" : "Filled.SportsSoccer"
        case .handIn: return "Filled.Inventory2"
        case .exam: return "Filled.EditNote"
        }
    }
}

struct TonightCard: View {
    let items: [TonightItem]
    let onTick: (String) -> Void
    let onOpen: () -> Void
    @Environment(LanguageStore.self) private var language

    var body: some View {
        let kurdish = language.language.isKurdish
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let colour = item.subject.map { SubjectColor.of($0) } ?? Tokens.accent
                MotionRow(action: { onTick(item.id) }) {
                    HStack(spacing: 12) {
                        TickCircle(on: item.done)
                        MaterialIcon(item.exam ? "Filled.EditNote" : SubjectIcon.of(item.subject), size: 17)
                            .foregroundStyle(colour)
                            .frame(width: 34, height: 34)
                            .glassTile(colour, shape: RR(10))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: item.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(item.done ? Tokens.textMuted : Tokens.text)
                                .lineLimit(1)
                            Text(verbatim: [item.subject.map { SubjectName.label($0, kurdish: kurdish) }, item.exam ? L("tonight_revise") : item.dueLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 13))
                                .foregroundStyle(item.overdue && !item.done ? Tokens.danger : Tokens.textMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onOpen() })
                if index < items.count - 1 { GroupDivider() }
            }
        }
        .darsMaterial(RR(16))
    }
}

struct ChangesCard: View {
    let items: [ChangeItem]
    let onOpen: (ChangeItem) -> Void
    @Environment(LanguageStore.self) private var language

    var body: some View {
        let kurdish = language.language.isKurdish
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let icon: String = item.kind == .posted ? "Filled.PostAdd" : (item.kind == .marked ? "Filled.Grade" : "Filled.Campaign")
                let tint: Color = item.kind == .posted ? HomeAccent.posted : (item.kind == .marked ? HomeAccent.marked : HomeAccent.announced)
                MotionRow(action: { onOpen(item) }) {
                    HStack(spacing: 12) {
                        MaterialIcon(icon, size: 17)
                            .foregroundStyle(tint)
                            .frame(width: 34, height: 34)
                            .glassTile(tint, shape: RR(10))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: title(item, kurdish: kurdish))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Tokens.text)
                                .lineLimit(1)
                            if let detail = item.detail {
                                Text(verbatim: item.kind == .posted ? SubjectName.label(detail, kurdish: kurdish) : detail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tokens.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                if index < items.count - 1 { GroupDivider() }
            }
        }
        .darsMaterial(RR(16))
    }

    private func title(_ item: ChangeItem, kurdish: Bool) -> String {
        switch item.kind {
        case .posted: return L("change_posted", item.title)
        case .marked: return L("change_marked", SubjectName.label(item.title, kurdish: kurdish))
        case .announced: return item.title
        }
    }
}

struct WeekStrip: View {
    let days: [WeekDay]
    let rate: Int?
    var streak = 0
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var bloom: CGFloat = 0

    var body: some View {
        let schoolDays = days.filter { $0.mark != .closed }
        let here = schoolDays.filter { $0.mark == .present || $0.mark == .late }.count
        let passed = schoolDays.filter { !$0.future }.count
        let complete = !schoolDays.isEmpty && here == schoolDays.count
        let fraction = schoolDays.isEmpty ? 0 : Double(here) / Double(schoolDays.count)
        MotionCard(action: onOpen) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        BloomRing(progress: bloom)
                        ProgressRing(progress: fraction, arc: complete ? Tokens.accent : Tokens.success, stroke: 8) {
                            Text(verbatim: "\(here)/\(schoolDays.count)").font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(Tokens.text)
                        }
                        .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: L(complete ? "home_week_complete" : "home_this_week"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.text)
                        Text(verbatim: streak > 1 ? L("home_streak", streak) : (passed == 0 ? L("home_week_not_started") : L("home_week_so_far", here, passed)))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Tokens.textMuted)
                    }
                    Spacer(minLength: 0)
                    if let rate {
                        Text(verbatim: L("home_attendance_rate", rate))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(rate >= 90 ? Tokens.success : (rate >= 75 ? Tokens.warning : Tokens.danger))
                    }
                }
                Spacer().frame(height: 12)
                HStack {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        DayDot(day: day)
                            .darsStagger(index, step: 0.045, delay: 0.1, rise: 4)
                        if index < days.count - 1 { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .onChange(of: complete) { _, now in
            guard now, !reduce else { return }
            HapticEngine.play(.success)
            bloom = 0
            withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.9)) { bloom = 1 }
        }
    }
}

private struct BloomRing: View, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        Circle()
            .strokeBorder(Tokens.accent, lineWidth: 2)
            .frame(width: 44, height: 44)
            .scaleEffect(1 + 1.1 * progress)
            .opacity(progress > 0 && progress < 1 ? Double((1 - progress) * 0.6) : 0)
    }
}

private struct DayDot: View {
    let day: WeekDay
    @Environment(LanguageStore.self) private var language

    var body: some View {
        let (colour, icon): (Color, String?) = {
            switch day.mark {
            case .present: return (Tokens.success, "Filled.Check")
            case .late: return (Tokens.warning, "Filled.Schedule")
            case .absent: return (Tokens.danger, "Filled.Close")
            case .closed: return (Tokens.textFaint, "Filled.Remove")
            case .none: return (Tokens.border, nil)
            }
        }()
        VStack(spacing: 6) {
            Text(verbatim: DayName.short(day.key, kurdish: language.language.isKurdish).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .darsTracking(0.4)
                .foregroundStyle(day.today ? Tokens.accentText : Tokens.textMuted)
            ZStack {
                Circle().fill(day.mark == .none ? Color.clear : colour.opacity(0.16))
                Circle().strokeBorder(day.today ? Tokens.accent : (day.mark == .none ? Tokens.border : .clear), lineWidth: day.today ? 1.5 : 1)
                if let icon {
                    MaterialIcon(icon, size: 15).foregroundStyle(colour)
                } else {
                    Text(verbatim: "\(day.dayOfMonth)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(day.future ? Tokens.textFaint : Tokens.textMuted)
                }
            }
            .frame(width: 30, height: 30)
        }
    }
}

struct MarksStrip: View {
    let marks: [RecentMark]
    let onOpen: () -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(marks.enumerated()), id: \.element.id) { index, mark in
                    MarkTile(mark: mark, onClick: onOpen)
                        .darsStagger(index, step: 0.05, delay: 0.08, rise: 6)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }
}

private struct MarkTile: View {
    let mark: RecentMark
    let onClick: () -> Void
    @Environment(LanguageStore.self) private var language

    var body: some View {
        let colour = SubjectColor.of(mark.subject)
        let fraction = mark.max > 0 ? min(max(mark.score / mark.max, 0), 1) : 0
        let grade = fraction >= 0.9 ? Tokens.success : (fraction >= 0.6 ? Tokens.text : Tokens.danger)
        MotionCard(action: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    MaterialIcon(SubjectIcon.of(mark.subject), size: 13)
                        .foregroundStyle(colour)
                        .frame(width: 24, height: 24)
                        .glassTile(colour, shape: RR(7))
                    Text(verbatim: SubjectName.label(mark.subject, kurdish: language.language.isKurdish))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(1)
                }
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(verbatim: trim(mark.score)).font(.system(size: 24, weight: .bold)).darsTracking(-0.8).monospacedDigit().foregroundStyle(grade)
                    Text(verbatim: " / " + trim(mark.max)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Tokens.textMuted)
                }
                .padding(.top, 10)
                Text(verbatim: mark.title.isEmpty ? mark.dateLabel : mark.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textMuted)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(12)
        }
        .frame(width: 140)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded(.down) ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct QrCodeView: View {
    let content: String
    var ink: Color = Color(hex: 0x1C1C1E)

    var body: some View {
        if let image = make() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(ink)
                .scaledToFit()
        }
    }

    private func make() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let inverted = output.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
        let scaled = inverted.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct FamilyCodeStrip: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MaterialIcon("Filled.FamilyRestroom", size: 20)
                    .foregroundStyle(Tokens.accentText)
                    .frame(width: 40, height: 40)
                    .glassTile(Tokens.accent, shape: RR(11))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: L("home_family_code")).font(.system(size: 13)).foregroundStyle(Tokens.textMuted)
                    Text(verbatim: code.uppercased()).font(.system(size: 24, weight: .bold)).darsTracking(2).monospacedDigit().foregroundStyle(Tokens.text)
                }
                Spacer(minLength: 0)
            }
            Text(verbatim: L("home_family_body")).font(.system(size: 13)).foregroundStyle(Tokens.textMuted).padding(.top, 8)
            QrCodeView(content: "dars://parent-join?code=" + code.uppercased())
                .frame(width: 150, height: 150)
                .padding(12)
                .background(Color.white, in: RR(16))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            HStack(spacing: 10) {
                MotionButton(title: LocalizedStringKey(L(copied ? "common_copied" : "chat_copy"))) {
                    HapticEngine.play(.success)
                    UIPasteboard.general.string = code.uppercased()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1600))
                        copied = false
                    }
                }
                .frame(maxWidth: .infinity)
                ShareLink(item: L("home_family_share", code, "dars://join/\(code)?family=1")) {
                    Text(verbatim: L("common_share"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Tokens.raised, in: RR(12))
                        .overlay(RR(12).strokeBorder(Tokens.border, lineWidth: 1))
                }
                .buttonStyle(DarsPress(scale: Motion.Scale.button, radius: 12))
            }
            .padding(.top, 12)
        }
        .padding(14)
        .darsMaterial(RR(16))
    }
}

struct StarsRow: View {
    let rating: Int
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                MaterialIcon(i <= rating ? "Filled.Star" : "Filled.StarOutline", size: size)
                    .foregroundStyle(i <= rating ? Tokens.accent : Tokens.textFaint)
            }
        }
    }
}

struct ReviewStrip: View {
    let review: WeekReview
    var body: some View {
        let colour = HomeAccent.review(review.tone)
        let toneKey: String = {
            switch review.tone {
            case .star: return "review_tone_star"
            case .great: return "review_tone_great"
            case .good: return "review_tone_good"
            case .fair: return "review_tone_fair"
            case .hard: return "review_tone_hard"
            }
        }()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: L(toneKey)).font(.system(size: 17, weight: .bold)).foregroundStyle(Tokens.text)
                    Text(verbatim: P("review_from_teachers", review.teachers) + " · " + String(format: "%.1f", review.average))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.textMuted)
                }
                Spacer(minLength: 0)
                StarsRow(rating: review.stars, size: 20)
            }
            ForEach(Array(review.notes.prefix(3).enumerated()), id: \.offset) { _, note in
                Text(verbatim: "\u{201C}" + note.trimmingCharacters(in: .whitespaces) + "\u{201D}")
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textSub)
                    .padding(.top, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colour.opacity(0.10), in: RR(16))
        .darsMaterial(RR(16))
    }
}
