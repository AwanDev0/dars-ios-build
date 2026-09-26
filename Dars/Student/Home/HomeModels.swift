import Foundation
import SwiftUI

enum DayPhase { case morning, atSchool, tomorrow }

enum DayMark { case present, absent, late, closed, none }

enum BagKind { case books, kit, handIn, exam }

enum ChangeKind { case posted, marked, announced }

enum ReviewTone { case star, great, good, fair, hard }

struct DayItem: Identifiable, Equatable {
    let id: String
    let time: String
    let end: String?
    let subject: String
    let room: String?
    let teacher: String?
    let isBreak: Bool
    let past: Bool
    var classLabel: String? = nil
    var away = false
    var cover: String? = nil
    var free: Bool { away && cover == nil }
}

struct BagItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let subject: String?
    let kind: BagKind
}

struct TonightItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subject: String?
    let dueLabel: String
    var done: Bool
    let exam: Bool
    var overdue = false
}

struct ChangeItem: Identifiable, Equatable {
    let id: String
    let kind: ChangeKind
    let title: String
    let detail: String?
}

struct WeekDay: Identifiable, Equatable {
    let key: String
    let date: String
    let dayOfMonth: Int
    let mark: DayMark
    let today: Bool
    let future: Bool
    var id: String { date }
}

struct RecentMark: Identifiable, Equatable {
    let id: String
    let subject: String
    let title: String
    let score: Double
    let max: Double
    let dateLabel: String
}

struct WeekReview: Equatable {
    let weekStart: String
    let average: Double
    let teachers: Int
    let notes: [String]
    var history: [Double]

    var stars: Int { min(max(Int(average.rounded()), 1), 5) }

    var tone: ReviewTone {
        let recent = Array(history.prefix(4))
        let hardWeeks = recent.filter { $0 < 2.5 }.count
        if average < 2.0 || hardWeeks >= 2 { return .hard }
        if recent.count >= 3 && recent.prefix(3).allSatisfy({ $0 >= 4.0 }) { return .star }
        if average >= 4.0 { return .great }
        if average >= 3.0 { return .good }
        if average >= 2.0 { return .fair }
        return .hard
    }
}

struct HomeNotice: Identifiable, Equatable {
    enum Kind { case announcement, unread, attendance }
    let id: String
    let kind: Kind
    let title: String
    let value: String
    let detail: String?
    let urgent: Bool
}

struct HomeTask: Identifiable, Equatable {
    let id: String
    let title: String
    let subject: String?
    let type: String?
    let dueDate: String?
    var done: Bool
    var isExam: Bool {
        let t = (type ?? "").lowercased()
        return t == "exam" || t == "quiz"
    }
}

enum SchoolWeek {
    static let days: Set<Int> = [1, 2, 3, 4, 5]
    static let opensHour = 8
    static let closesHour = 12

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static func isSchoolDay(_ date: Date, closures: Set<String>) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return days.contains(weekday) && !closures.contains(DayKey.string(date))
    }

    static func nextSchoolDay(_ now: Date, closures: Set<String>) -> Date {
        let hour = calendar.component(.hour, from: now)
        var date = hour < opensHour ? now.startOfDay : now.startOfDay.adding(days: 1)
        var guardCount = 0
        while !isSchoolDay(date, closures: closures) && guardCount < 21 {
            date = date.adding(days: 1)
            guardCount += 1
        }
        return date
    }

    static func phase(_ now: Date, closures: Set<String>) -> DayPhase {
        let hour = calendar.component(.hour, from: now)
        if !isSchoolDay(now, closures: closures) { return .tomorrow }
        if hour < opensHour { return .morning }
        if hour < closesHour { return .atSchool }
        return .tomorrow
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

enum BagRules {
    static let separator = "|"
    private static let kitSubjects: Set<String> = ["PE", "Physical Education", "Sport", "Sports"]
    private static let artSubjects: Set<String> = ["Art", "Arts", "Drawing"]

    static func derive(target: Date, lessons: [DayItem], work: [HomeTask]) -> [BagItem] {
        var out: [BagItem] = []
        var seen = Set<String>()
        let subjects = lessons.filter { !$0.isBreak && !$0.free }
            .map { $0.subject.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if !subjects.isEmpty {
            out.append(BagItem(id: "books", title: "", detail: subjects.joined(separator: separator), subject: nil, kind: .books))
        }
        if let pe = subjects.first(where: { kitSubjects.contains($0) }) {
            out.append(BagItem(id: "kit:pe", title: "", detail: nil, subject: pe, kind: .kit))
        }
        if let art = subjects.first(where: { artSubjects.contains($0) }) {
            out.append(BagItem(id: "kit:art", title: "", detail: nil, subject: art, kind: .kit))
        }
        let today = Date().startOfDay
        let due = work.filter { t in
            guard let d = DayKey.date(t.dueDate) else { return false }
            return d <= target && d >= today
        }
        for t in due where t.isExam {
            out.append(BagItem(id: "exam:\(t.id)", title: t.title, detail: t.subject, subject: t.subject, kind: .exam))
        }
        for t in due where !t.isExam {
            out.append(BagItem(id: "due:\(t.id)", title: t.title, detail: t.subject, subject: t.subject, kind: .handIn))
        }
        return out
    }
}

enum NowState {
    case inClass(DayItem, progress: Double, leftMinutes: Int)
    case next(DayItem, inMinutes: Int)
    case done
    case free
    case loading
}

func minutesOfDay(_ raw: String?) -> Int? {
    guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    let parts = raw.split(separator: ":")
    guard let h = parts.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else { return nil }
    let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
    return h * 60 + m
}

func nowState(_ day: [DayItem], loading: Bool, now: Date) -> NowState {
    if loading { return .loading }
    let lessons = day.filter { !$0.isBreak && !$0.free }
    if lessons.isEmpty { return .free }
    let c = Calendar.current.dateComponents([.hour, .minute], from: now)
    let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    if let running = lessons.first(where: { item in
        guard let from = minutesOfDay(item.time), let to = minutesOfDay(item.end) else { return false }
        return minutes >= from && minutes < to
    }), let from = minutesOfDay(running.time), let to = minutesOfDay(running.end) {
        return .inClass(running, progress: Double(minutes - from) / Double(max(to - from, 1)), leftMinutes: to - minutes)
    }
    let upcoming = lessons.compactMap { item in minutesOfDay(item.time).map { ($0, item) } }
        .filter { $0.0 > minutes }
        .min { $0.0 < $1.0 }
    if let upcoming { return .next(upcoming.1, inMinutes: upcoming.0 - minutes) }
    return .done
}

enum DarsDate {
    static func longDate(_ iso: String?, kurdish: Bool) -> String {
        guard let date = DayKey.date(iso) else { return "" }
        let day = Calendar.current.component(.day, from: date)
        let year = Calendar.current.component(.year, from: date)
        if kurdish {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ckb")
            f.dateFormat = "LLLL"
            return "\(day)ی \(f.string(from: date))ی \(year)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    static func todayLine(kurdish: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: kurdish ? "ckb" : "en_GB")
        f.dateFormat = "EEEE, d MMMM"
        let s = f.string(from: Date())
        return kurdish ? westernDigits(s) : s
    }

    static func westernDigits(_ s: String) -> String {
        let eastern = Array("٠١٢٣٤٥٦٧٨٩")
        let persian = Array("۰۱۲۳۴۵۶۷۸۹")
        return String(s.map { ch in
            if let i = eastern.firstIndex(of: ch) { return Character(String(i)) }
            if let i = persian.firstIndex(of: ch) { return Character(String(i)) }
            return ch
        })
    }
}

enum HomeAccent {
    static func subject(_ subject: String?) -> Color { SubjectColor.of(subject) }
    static let posted = Color(hex: 0x5856D6)
    static let marked = Color(hex: 0x34C759)
    static let announced = Color(hex: 0xAF52DE)
    static let due = Color(hex: 0xFF9500)
    static let attendance = Color(hex: 0x009688)
    static let unread = Color(hex: 0x007AFF)

    static func review(_ tone: ReviewTone) -> Color {
        switch tone {
        case .star: return Color(hex: 0xAF52DE)
        case .great: return Tokens.success
        case .good: return Tokens.accent
        case .fair: return Tokens.warning
        case .hard: return Tokens.danger
        }
    }
}
