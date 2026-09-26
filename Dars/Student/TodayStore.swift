import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class TodayStore {
    private(set) var periods: [ScheduleItem] = []
    private(set) var announcements: [Announcement] = []
    private(set) var loading = true
    private(set) var error: DarsError?

    private let client = SupabaseService.client

    func load(for profile: Profile) async {
        error = nil
        do {
            async let news: [Announcement] = try await client
                .from("announcements")
                .select(Announcement.columns)
                .order("created_at", ascending: false)
                .limit(5)
                .execute()
                .value

            var items: [ScheduleItem] = []
            if profile.role == .student {
                let rows: [StudentClass] = try await client
                    .rpc("student_class", params: ["uid": profile.id.uuidString])
                    .execute()
                    .value
                if let classId = rows.first?.classId {
                    items = try await client
                        .from("schedule_items")
                        .select(ScheduleItem.columns)
                        .eq("class_id", value: classId)
                        .eq("day_of_week", value: Self.todayKey())
                        .order("sort_order")
                        .execute()
                        .value
                }
            }
            periods = items
            announcements = try await news
        } catch let e as URLError {
            error = e.code == .notConnectedToInternet || e.code == .timedOut ? .network : .server(e.localizedDescription)
        } catch {
            self.error = .server(String(describing: error))
        }
        loading = false
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    var now: ScheduleItem? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let clock = f.string(from: Date())
        return periods.first { !$0.isBreak && ($0.startTime ?? "") <= clock && clock < ($0.endTime ?? "") }
    }
}

struct ScheduleItem: Codable, Identifiable, Equatable, Sendable {
    static let columns = "id, day_of_week, subject, teacher, room, start_time, end_time, is_break, sort_order"

    let id: UUID
    let dayOfWeek: String?
    let subject: String?
    let teacher: String?
    let room: String?
    let startTime: String?
    let endTime: String?
    let isBreak: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case dayOfWeek = "day_of_week"
        case subject, teacher, room
        case startTime = "start_time"
        case endTime = "end_time"
        case isBreak = "is_break"
        case sortOrder = "sort_order"
    }
}

struct Announcement: Codable, Identifiable, Equatable, Sendable {
    static let columns = "id, title, body, scope, created_at"

    let id: UUID
    let title: String?
    let body: String?
    let scope: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body, scope
        case createdAt = "created_at"
    }
}

struct StudentClass: Codable, Sendable {
    let classId: UUID
    let grade: String?

    enum CodingKeys: String, CodingKey {
        case classId = "class_id"
        case grade
    }
}
