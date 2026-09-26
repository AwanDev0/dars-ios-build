import Foundation
import Observation
import Supabase

enum DarsTime {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = fractional.date(from: raw) { return d }
        if let d = plain.date(from: raw) { return d }
        let normalized = raw.replacingOccurrences(of: " ", with: "T")
        if let d = fractional.date(from: normalized) ?? plain.date(from: normalized) { return d }
        if let d = plain.date(from: normalized + "Z") { return d }
        return DayKey.date(raw)
    }
}

@MainActor
@Observable
final class StudentHomeStore {
    private(set) var loading = true
    private(set) var refreshing = false
    private(set) var error: String?
    private(set) var phase: DayPhase = .morning
    private(set) var targetDay: Date?
    private(set) var targetDayLabel: String?
    private(set) var targetDayKey: String?
    private(set) var closureReason: String?
    private(set) var bag: [BagItem] = []
    private(set) var bagTicked: Set<String> = []
    private(set) var tonight: [TonightItem] = []
    private(set) var changes: [ChangeItem] = []
    private(set) var restOfDay: [DayItem] = []
    private(set) var notices: [HomeNotice] = []
    private(set) var scheduleMissing = false
    private(set) var unreadMessages = 0
    private(set) var week: [WeekDay] = []
    private(set) var weekRate: Int?
    private(set) var streak = 0
    private(set) var familyCode: String?
    private(set) var review: WeekReview?
    private(set) var marks: [RecentMark] = []
    private(set) var birthday = false

    var bagPacked: Bool { !bag.isEmpty && bag.allSatisfy { bagTicked.contains($0.id) } }

    private let client = SupabaseService.client
    private var loaded = false

    private struct MemberRow: Decodable { let class_id: UUID? }
    private struct ScheduleRow: Decodable {
        let id: UUID
        let subject: String?
        let start_time: String?
        let end_time: String?
        let teacher: String?
        let room: String?
        let is_break: Bool?
        let sort_order: Int?
        let teacher_id: UUID?
    }
    private struct ClosureRow: Decodable { let id: UUID; let date: String; let kind: String?; let reason: String?; let reason_ku: String? }
    private struct AssignmentRow: Decodable { let id: UUID; let title: String?; let subject: String?; let type: String?; let due_date: String? }
    private struct CompletionRow: Decodable { let assignment_id: UUID? }
    private struct AbsenceRow: Decodable { let id: UUID; let teacher_id: UUID; let date: String; let cover_teacher_id: UUID? }
    private struct CoverRow: Decodable { let id: UUID; let full_name: String?; let full_name_ku: String? }
    private struct AttendanceRow: Decodable { let id: UUID; let status: String?; let date: String?; let note: String? }
    private struct Assessment: Decodable { let subject: String?; let title: String?; let max_score: Double?; let date: String? }
    private struct ResultRow: Decodable { let assessment_id: UUID; let score: Double?; let updated_at: String?; let assessments_v2: Assessment? }
    private struct PostRow: Decodable { let id: UUID; let title: String?; let subject: String? }
    private struct AnnouncementRow: Decodable { let id: UUID; let title: String?; let body: String?; let created_at: String? }
    private struct UnreadRow: Decodable { let conversation_id: UUID; let last_read_at: String?; let left_at: String? }
    private struct ConversationTime: Decodable { let id: UUID; let last_message_at: String? }
    private struct FamilyRow: Decodable { let family_code: String? }
    private struct BornRow: Decodable { let date_of_birth: String? }
    private struct IdRow: Decodable { let id: UUID }
    private struct ReviewRow: Decodable { let week_start: String; let average: Double; let teachers: Int; let notes: [String]?; let history: [Double]? }
    private struct CompletionInsert: Encodable, Sendable { let assignment_id: UUID; let student_id: UUID }

    private var me: UUID?

    func load(_ profile: Profile, kurdish: Bool) async {
        me = profile.id
        if loaded { refreshing = true }
        error = nil
        let now = Date()
        let today = now.startOfDay
        let todayKey = SchoolWeek.dayKey(now)

        let classId = await classId(for: profile.id)
        let closuresAhead = await closures(from: today, to: nil, limit: 30)
        let closed = Set(closuresAhead.map { String($0.date.prefix(10)) })
        phase = SchoolWeek.phase(now, closures: closed)
        let target = SchoolWeek.nextSchoolDay(now, closures: closed)
        targetDay = target
        targetDayLabel = DarsDate.longDate(DayKey.string(target), kurdish: kurdish)
        targetDayKey = SchoolWeek.dayKey(target)
        let plainTomorrow = today.adding(days: 1)
        if phase == .tomorrow, !Calendar.current.isDate(target, inSameDayAs: plainTomorrow),
           let c = closuresAhead.first(where: { String($0.date.prefix(10)) == DayKey.string(plainTomorrow) }) {
            let reason = (kurdish ? (c.reason_ku ?? c.reason) : c.reason) ?? ""
            closureReason = reason.isEmpty ? (c.kind ?? "") : reason
        } else {
            closureReason = nil
        }

        async let todaySchedule = schedule(classId, day: todayKey)
        async let targetSchedule = schedule(classId, day: SchoolWeek.dayKey(target))
        async let allTasks = tasks(classId, student: profile.id)
        async let absences = away(on: [DayKey.string(today), DayKey.string(target)], kurdish: kurdish)
        async let unread = unreadCount(profile.id)
        async let attendanceToday = latestAttendance(profile.id)
        async let announcement = latestAnnouncement()
        async let weekRows = attendance(profile.id, from: weekStart(today), to: weekStart(today).adding(days: 4))
        async let weekClosures = closures(from: weekStart(today), to: weekStart(today).adding(days: 4), limit: 60)
        async let rate = attendanceRate(profile.id)
        async let recent = recentMarks(profile.id)
        async let code = familyCodeFor(profile.id)
        async let reviewed = weekReview(profile.id)
        async let history = attendance(profile.id, from: today.adding(days: -70), to: today)
        async let pastClosures = closures(from: today.adding(days: -70), to: today, limit: 60)
        async let hasSchedule = schoolHasSchedule()
        async let born = isBirthday(profile.id)

        let away = await absences
        let awayToday = away.compactMapValues { $0[DayKey.string(today)] }
        let awayTarget = away.compactMapValues { $0[DayKey.string(target)] }
        let todayRows = await todaySchedule
        let targetRows = Calendar.current.isDate(target, inSameDayAs: today) ? todayRows : await targetSchedule

        restOfDay = phase == .tomorrow
            ? dayItems(targetRows, past: false, away: awayTarget)
            : dayItems(todayRows, past: nil, away: awayToday)
        let targetItems = dayItems(targetRows, past: false, away: awayTarget)
        let taskList = await allTasks
        bag = BagRules.derive(target: target, lessons: targetItems, work: taskList.filter { !$0.done })
        bagTicked = ticks(for: target)

        tonight = taskList
            .filter { t in DayKey.date(t.dueDate).map { $0 <= target } ?? false }
            .sorted { a, b in a.done == b.done ? (a.dueDate ?? "") < (b.dueDate ?? "") : !a.done }
            .map { t in
                let due = DayKey.date(t.dueDate)
                let late = !t.done && (due.map { $0 < today } ?? false)
                return TonightItem(
                    id: t.id,
                    title: t.title,
                    subject: t.subject,
                    dueLabel: late ? L("common_overdue") : (t.dueDate ?? ""),
                    done: t.done,
                    exam: t.isExam,
                    overdue: late
                )
            }

        changes = phase == .tomorrow ? await changesToday(profile.id, classId: classId) : []

        let rows = Dictionary(await weekRows.map { (String(($0.date ?? "").prefix(10)), $0) }, uniquingKeysWith: { a, _ in a })
        let closedWeek = Set(await weekClosures.map { String($0.date.prefix(10)) })
        let start = weekStart(today)
        week = (0..<5).map { i in
            let date = start.adding(days: i)
            let iso = DayKey.string(date)
            let status = rows[iso]?.status
            let mark: DayMark
            if closedWeek.contains(iso) { mark = .closed }
            else if status == "present" { mark = .present }
            else if status == "late" { mark = .late }
            else if status == "absent" { mark = .absent }
            else { mark = .none }
            return WeekDay(
                key: SchoolWeek.dayKey(date),
                date: iso,
                dayOfMonth: Calendar.current.component(.day, from: date),
                mark: mark,
                today: Calendar.current.isDate(date, inSameDayAs: today),
                future: date > today
            )
        }
        weekRate = await rate
        familyCode = await code
        review = await reviewed

        let historyRows = Dictionary(await history.map { (String(($0.date ?? "").prefix(10)), $0) }, uniquingKeysWith: { a, _ in a })
        let skipped = Set(await pastClosures.map { String($0.date.prefix(10)) })
        var d = today
        var count = 0
        var walked = 0
        while walked < 70 {
            let key = DayKey.string(d)
            let weekday = Calendar.current.component(.weekday, from: d)
            if SchoolWeek.days.contains(weekday) && !skipped.contains(key) {
                let status = historyRows[key]?.status
                if status == "present" || status == "late" {
                    count += 1
                } else if status == nil && Calendar.current.isDate(d, inSameDayAs: today) {
                } else {
                    break
                }
            }
            d = d.adding(days: -1)
            walked += 1
        }
        streak = count

        marks = await recent.compactMap { row in
            guard let score = row.score else { return nil }
            return RecentMark(
                id: row.assessment_id.uuidString,
                subject: row.assessments_v2?.subject ?? "",
                title: row.assessments_v2?.title ?? "",
                score: score,
                max: row.assessments_v2?.max_score ?? 100,
                dateLabel: DarsDate.longDate(row.assessments_v2?.date, kurdish: kurdish)
            )
        }

        var notes: [HomeNotice] = []
        if let record = await attendanceToday {
            let status = record.status ?? ""
            notes.append(HomeNotice(id: "attendance", kind: .attendance, title: L("card_attendance"), value: status.prefix(1).uppercased() + status.dropFirst(), detail: record.note, urgent: status == "absent"))
        }
        let unreadCount = await unread
        unreadMessages = unreadCount
        if unreadCount > 0 {
            notes.append(HomeNotice(id: "unread", kind: .unread, title: L("card_messages"), value: P("card_unread_conversations", unreadCount), detail: nil, urgent: false))
        }
        if let a = await announcement {
            notes.append(HomeNotice(id: "announcement-\(a.id)", kind: .announcement, title: L("card_from_school"), value: a.title ?? "", detail: nil, urgent: false))
        }
        notices = notes
        scheduleMissing = !(await hasSchedule)
        birthday = await born

        loading = false
        refreshing = false
        loaded = true
    }

    func tickBag(_ id: String) {
        guard let day = targetDay else { return }
        var next = bagTicked
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        bagTicked = next
        UserDefaults.standard.set(DayKey.string(day), forKey: "dars.bag.day")
        UserDefaults.standard.set(Array(next), forKey: "dars.bag.ticks")
        if bagPacked { HapticEngine.play(.success) }
    }

    func tickWork(_ id: String) async {
        guard let index = tonight.firstIndex(where: { $0.id == id }), let me, let uuid = UUID(uuidString: id) else { return }
        let was = tonight[index].done
        tonight[index].done = !was
        do {
            if !was {
                try await client.from("completions").insert(CompletionInsert(assignment_id: uuid, student_id: me)).execute()
            } else {
                try await client.from("completions").delete().eq("assignment_id", value: uuid).eq("student_id", value: me).execute()
            }
        } catch {
            if let i = tonight.firstIndex(where: { $0.id == id }) { tonight[i].done = was }
        }
    }

    private func ticks(for day: Date) -> Set<String> {
        guard UserDefaults.standard.string(forKey: "dars.bag.day") == DayKey.string(day) else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: "dars.bag.ticks") ?? [])
    }

    private func weekStart(_ today: Date) -> Date {
        let weekday = Calendar.current.component(.weekday, from: today)
        return today.adding(days: -(weekday - 1))
    }

    private func dayItems(_ rows: [ScheduleRow], past: Bool?, away: [UUID: (String?)]) -> [DayItem] {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return rows.map { row in
            let absent = row.teacher_id.flatMap { away[$0] }
            let started = minutesOfDay(row.start_time).map { $0 < nowMinutes } ?? false
            return DayItem(
                id: row.id.uuidString,
                time: String((row.start_time ?? "").prefix(5)),
                end: row.end_time.map { String($0.prefix(5)) },
                subject: row.subject ?? "",
                room: row.room,
                teacher: row.teacher,
                isBreak: row.is_break ?? false,
                past: past ?? started,
                away: absent != nil,
                cover: absent ?? nil
            )
        }
    }

    private func classId(for user: UUID) async -> UUID? {
        let rows: [MemberRow] = (try? await client.from("class_members").select("class_id, user_id").eq("user_id", value: user).limit(1).execute().value) ?? []
        return rows.first?.class_id
    }

    private func schedule(_ classId: UUID?, day: String) async -> [ScheduleRow] {
        guard let classId else { return [] }
        let rows: [ScheduleRow] = (try? await client.from("schedule_items")
            .select("id, subject, start_time, end_time, teacher, room, is_break, sort_order, teacher_id")
            .eq("class_id", value: classId)
            .eq("day_of_week", value: day)
            .order("sort_order")
            .execute().value) ?? []
        return rows.sorted { (minutesOfDay($0.start_time) ?? Int.max) < (minutesOfDay($1.start_time) ?? Int.max) }
    }

    private func closures(from: Date, to: Date?, limit: Int) async -> [ClosureRow] {
        var query = client.from("school_closures").select("id, date, kind, reason, reason_ku").gte("date", value: DayKey.string(from))
        if let to { query = query.lte("date", value: DayKey.string(to)) }
        return (try? await query.order("date").limit(limit).execute().value) ?? []
    }

    private func tasks(_ classId: UUID?, student: UUID) async -> [HomeTask] {
        guard let classId else { return [] }
        let rows: [AssignmentRow] = (try? await client.from("assignments").select("id, title, subject, type, due_date").eq("class_id", value: classId).order("due_date").execute().value) ?? []
        let done: [CompletionRow] = (try? await client.from("completions").select("assignment_id, student_id").eq("student_id", value: student).execute().value) ?? []
        let doneIds = Set(done.compactMap { $0.assignment_id })
        return rows.map { HomeTask(id: $0.id.uuidString, title: $0.title ?? "", subject: $0.subject, type: $0.type, dueDate: $0.due_date, done: doneIds.contains($0.id)) }
    }

    private func away(on dates: [String], kurdish: Bool) async -> [UUID: [String: String?]] {
        let rows: [AbsenceRow] = (try? await client.from("teacher_absences").select("id, teacher_id, date, reason, cover_teacher_id").in("date", values: dates).execute().value) ?? []
        guard !rows.isEmpty else { return [:] }
        let coverIds = Array(Set(rows.compactMap { $0.cover_teacher_id }))
        var covers: [UUID: CoverRow] = [:]
        if !coverIds.isEmpty {
            let people: [CoverRow] = (try? await client.from("profiles").select("id, full_name, full_name_ku").in("id", values: coverIds.map { $0.uuidString }).execute().value) ?? []
            covers = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        var out: [UUID: [String: String?]] = [:]
        for row in rows {
            let cover = row.cover_teacher_id.flatMap { covers[$0] }
            let name: String? = cover.map { kurdish && !($0.full_name_ku ?? "").isEmpty ? $0.full_name_ku : $0.full_name } ?? nil
            out[row.teacher_id, default: [:]][String(row.date.prefix(10))] = .some(name)
        }
        return out
    }

    private func unreadCount(_ user: UUID) async -> Int {
        let members: [UnreadRow] = (try? await client.from("conversation_members").select("conversation_id, last_read_at, left_at").eq("user_id", value: user).execute().value) ?? []
        let active = members.filter { $0.left_at == nil }
        guard !active.isEmpty else { return 0 }
        let conversations: [ConversationTime] = (try? await client.from("conversations").select("id, last_message_at").in("id", values: active.map { $0.conversation_id.uuidString }).execute().value) ?? []
        let readBy = Dictionary(active.map { ($0.conversation_id, $0.last_read_at) }, uniquingKeysWith: { a, _ in a })
        return conversations.filter { c in
            guard let last = DarsTime.parse(c.last_message_at) else { return false }
            guard let read = DarsTime.parse(readBy[c.id] ?? nil) else { return true }
            return last > read
        }.count
    }

    private func latestAttendance(_ student: UUID) async -> AttendanceRow? {
        let rows: [AttendanceRow] = (try? await client.from("attendance").select("id, student_id, status, date, note").eq("student_id", value: student).order("date", ascending: false).limit(1).execute().value) ?? []
        guard let row = rows.first, let d = DayKey.date(row.date), Calendar.current.isDateInToday(d) else { return nil }
        return row
    }

    private func latestAnnouncement() async -> AnnouncementRow? {
        let rows: [AnnouncementRow] = (try? await client.from("announcements").select("id, title, body, created_at").order("created_at", ascending: false).limit(1).execute().value) ?? []
        return rows.first
    }

    private func attendance(_ student: UUID, from: Date, to: Date) async -> [AttendanceRow] {
        (try? await client.from("attendance").select("id, student_id, status, date, note").eq("student_id", value: student).gte("date", value: DayKey.string(from)).lte("date", value: DayKey.string(to)).order("date").limit(60).execute().value) ?? []
    }

    private func attendanceRate(_ student: UUID) async -> Int? {
        let rows: [AttendanceRow] = (try? await client.from("attendance").select("id, student_id, status, date, note").eq("student_id", value: student).execute().value) ?? []
        guard !rows.isEmpty else { return nil }
        let here = rows.filter { $0.status == "present" || $0.status == "late" }.count
        return Int((Double(here) * 100 / Double(rows.count)).rounded())
    }

    private func recentMarks(_ student: UUID) async -> [ResultRow] {
        (try? await client.from("assessment_results_v2")
            .select("assessment_id, student_id, score, updated_at, assessments_v2(subject, title, max_score, date)")
            .eq("student_id", value: student)
            .order("updated_at", ascending: false)
            .limit(6)
            .execute().value) ?? []
    }

    private func familyCodeFor(_ student: UUID) async -> String? {
        let rows: [FamilyRow] = (try? await client.from("profiles").select("id, family_code").eq("id", value: student).limit(1).execute().value) ?? []
        guard let code = rows.first?.family_code, !code.isEmpty else { return nil }
        return code
    }

    private func weekReview(_ student: UUID) async -> WeekReview? {
        let rows: [ReviewRow] = (try? await client.rpc("student_week_review", params: ["p_student": student.uuidString]).execute().value) ?? []
        guard let dto = rows.first, let start = DayKey.date(dto.week_start) else { return nil }
        if start < Date().startOfDay.adding(days: -13) { return nil }
        let history = (dto.history ?? []).isEmpty ? [dto.average] : dto.history!
        return WeekReview(weekStart: String(dto.week_start.prefix(10)), average: dto.average, teachers: dto.teachers, notes: dto.notes ?? [], history: history)
    }

    private func schoolHasSchedule() async -> Bool {
        let rows: [IdRow] = (try? await client.from("schedule_items").select("id").limit(1).execute().value) ?? []
        return !rows.isEmpty
    }

    private func isBirthday(_ student: UUID) async -> Bool {
        let rows: [BornRow] = (try? await client.from("student_records").select("student_id, date_of_birth").eq("student_id", value: student).limit(1).execute().value) ?? []
        guard let born = DayKey.date(rows.first?.date_of_birth) else { return false }
        let a = Calendar.current.dateComponents([.month, .day], from: born)
        let b = Calendar.current.dateComponents([.month, .day], from: Date())
        return a.month == b.month && a.day == b.day
    }

    private func changesToday(_ student: UUID, classId: UUID?) async -> [ChangeItem] {
        let since = ISO8601DateFormatter().string(from: Date().startOfDay)
        var posted: [PostRow] = []
        if let classId {
            posted = (try? await client.from("assignments").select("id, title, subject, type, due_date, created_at").eq("class_id", value: classId).gte("created_at", value: since).order("created_at", ascending: false).limit(10).execute().value) ?? []
        }
        let marked: [ResultRow] = (try? await client.from("assessment_results_v2")
            .select("assessment_id, student_id, score, updated_at, assessments_v2(subject, title, max_score, date)")
            .eq("student_id", value: student)
            .gte("updated_at", value: since)
            .order("updated_at", ascending: false)
            .limit(10)
            .execute().value) ?? []
        let announced: [AnnouncementRow] = (try? await client.from("announcements").select("id, title, body, created_at").gte("created_at", value: since).order("created_at", ascending: false).limit(5).execute().value) ?? []
        var out: [ChangeItem] = []
        out += posted.map { ChangeItem(id: "post:\($0.id)", kind: .posted, title: $0.title ?? "", detail: $0.subject) }
        out += marked.map { ChangeItem(id: "mark:\($0.assessment_id)", kind: .marked, title: $0.assessments_v2?.subject ?? "", detail: $0.assessments_v2?.title) }
        out += announced.map { ChangeItem(id: "ann:\($0.id)", kind: .announced, title: $0.title ?? "", detail: $0.body.map { String($0.prefix(80)) }) }
        return out
    }
}
