import Foundation
import Supabase

enum DarsData {
    static let client = SupabaseService.client

    static func profiles(ids: [UUID]) async throws -> [Profile] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("profiles").select(Profile.columns)
            .in("id", values: ids.map { $0.uuidString }).order("full_name").execute().value
    }

    static func classes(ids: [UUID]) async throws -> [ClassRow] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("classes").select(ClassRow.columns).in("id", values: ids.map { $0.uuidString }).execute().value
    }

    static func allClasses() async throws -> [ClassRow] {
        let rows: [ClassRow] = try await client.from("classes").select(ClassRow.columns).execute().value
        return rows.sorted { ($0.gradeNumber, $0.section ?? "") < ($1.gradeNumber, $1.section ?? "") }
    }

    static func members(classId: UUID) async throws -> [Profile] {
        let rows: [ClassMemberRow] = try await client.from("class_members").select("class_id, user_id").eq("class_id", value: classId).execute().value
        return try await profiles(ids: rows.map { $0.userId })
    }

    static func memberCounts(classIds: [UUID]) async throws -> [UUID: Int] {
        guard !classIds.isEmpty else { return [:] }
        let rows: [ClassMemberRow] = try await client.from("class_members").select("class_id, user_id").in("class_id", values: classIds.map { $0.uuidString }).execute().value
        return rows.reduce(into: [:]) { $0[$1.classId, default: 0] += 1 }
    }

    static func school(_ id: UUID?) async throws -> SchoolRow? {
        guard let id else { return nil }
        let rows: [SchoolRow] = try await client.from("schools").select(SchoolRow.columns).eq("id", value: id).execute().value
        return rows.first
    }

    static func knock<B: Encodable & Sendable>(_ body: B) {
        Task.detached {
            do { try await SupabaseService.client.functions.invoke("push-send", options: FunctionInvokeOptions(body: body)) } catch {}
        }
    }

    struct PushPost: Encodable, Sendable { let kind = "post"; let table: String; let post_id: UUID }
    struct PushGrade: Encodable, Sendable { let kind = "grade"; let assessment_id: UUID; let student_id: UUID }
    struct PushAbsence: Encodable, Sendable { let kind = "absence"; let attendance_id: UUID }
}

enum SchoolYear {
    static func current(_ date: Date = Date()) -> String {
        let y = Calendar.current.component(.year, from: date)
        let m = Calendar.current.component(.month, from: date)
        return m >= 9 ? "\(y)-\(y + 1)" : "\(y - 1)-\(y)"
    }
}

enum DayKey {
    private static let f: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f }()
    static func string(_ d: Date) -> String { f.string(from: d) }
    static func date(_ s: String?) -> Date? { s.flatMap { f.date(from: String($0.prefix(10))) } }
}

struct ClassRow: Codable, Identifiable, Hashable, Sendable {
    static let columns = "id, name, grade, section, school_id"
    let id: UUID
    let name: String?
    let grade: String?
    let section: String?
    let schoolId: UUID?
    var label: String {
        let l = (grade ?? "") + (section ?? "")
        return l.isEmpty ? (name ?? "—") : l
    }
    var gradeNumber: Int { Int(grade ?? "") ?? Int.max }
    enum CodingKeys: String, CodingKey { case id, name, grade, section; case schoolId = "school_id" }
}

struct ClassMemberRow: Codable, Sendable {
    let classId: UUID
    let userId: UUID
    enum CodingKeys: String, CodingKey { case classId = "class_id"; case userId = "user_id" }
}

struct SchoolRow: Codable, Identifiable, Sendable {
    static let columns = "id, name, name_ku, code, current_semester, school_year, owner_name, owner_title, address, phone, email, website, attendance_any_day"
    let id: UUID
    var name: String?
    var nameKu: String?
    let code: String?
    let currentSemester: String?
    let schoolYear: String?
    var ownerName: String?
    var ownerTitle: String?
    var address: String?
    var phone: String?
    var email: String?
    var website: String?
    let attendanceAnyDay: Bool?
    var semester: String { (currentSemester?.isEmpty == false) ? currentSemester! : "1" }
    var year: String { (schoolYear?.isEmpty == false) ? schoolYear! : SchoolYear.current() }
    enum CodingKeys: String, CodingKey {
        case id, name, code, address, phone, email, website
        case nameKu = "name_ku"
        case currentSemester = "current_semester"
        case schoolYear = "school_year"
        case ownerName = "owner_name"
        case ownerTitle = "owner_title"
        case attendanceAnyDay = "attendance_any_day"
    }
}

struct TeacherAssignmentRow: Codable, Identifiable, Sendable {
    static let columns = "id, teacher_id, class_id, subject, classes(id, name, grade, section, school_id)"
    let id: UUID
    let teacherId: UUID?
    let classId: UUID?
    let subject: String?
    let classes: ClassRow?
    enum CodingKeys: String, CodingKey { case id, subject, classes; case teacherId = "teacher_id"; case classId = "class_id" }
}

struct AttendanceRow: Codable, Identifiable, Sendable {
    static let columns = "id, student_id, class_id, date, status, note"
    let id: UUID
    let studentId: UUID
    let classId: UUID?
    let date: String
    let status: String
    let note: String?
    enum CodingKeys: String, CodingKey { case id, date, status, note; case studentId = "student_id"; case classId = "class_id" }
}

enum AttendanceStatus: String, CaseIterable, Identifiable {
    case present, absent, late, excused
    var id: String { rawValue }
    var label: LocalizedStringKeyBox {
        switch self {
        case .present: return "Present"
        case .absent: return "Absent"
        case .late: return "Late"
        case .excused: return "Excused"
        }
    }
    var symbol: String {
        switch self {
        case .present: return "checkmark"
        case .absent: return "xmark"
        case .late: return "clock"
        case .excused: return "doc.text"
        }
    }
}

typealias LocalizedStringKeyBox = String

struct AssessmentRow: Codable, Identifiable, Sendable {
    static let columns = "id, class_id, subject, semester, school_year, type, title, date, max_score, archived_at, created_by"
    let id: UUID
    let classId: UUID?
    let subject: String?
    let semester: String?
    let schoolYear: String?
    let type: String?
    let title: String?
    let date: String?
    let maxScore: Double?
    let archivedAt: String?
    let createdBy: UUID?
    enum CodingKeys: String, CodingKey {
        case id, subject, semester, type, title, date
        case classId = "class_id"; case schoolYear = "school_year"; case maxScore = "max_score"; case archivedAt = "archived_at"; case createdBy = "created_by"
    }
}

struct ResultRow: Codable, Sendable {
    let assessmentId: UUID
    let studentId: UUID
    let score: Double?
    enum CodingKeys: String, CodingKey { case score; case assessmentId = "assessment_id"; case studentId = "student_id" }
}

struct AnnouncementRow: Codable, Identifiable, Sendable {
    static let columns = "id, school_id, author_id, class_id, scope, title, body, pinned, created_at, attachment_url, attachment_name"
    let id: UUID
    let schoolId: UUID?
    let authorId: UUID?
    let classId: UUID?
    let scope: String?
    let title: String?
    let body: String?
    let pinned: Bool?
    let createdAt: String?
    let attachmentUrl: String?
    let attachmentName: String?
    var date: Date? { createdAt.map(ISO8601.parse) }
    enum CodingKeys: String, CodingKey {
        case id, scope, title, body, pinned
        case schoolId = "school_id"; case authorId = "author_id"; case classId = "class_id"; case createdAt = "created_at"
        case attachmentUrl = "attachment_url"; case attachmentName = "attachment_name"
    }
}

struct PersonRow: Identifiable, Hashable {
    let profile: Profile
    var detail: String?
    var id: UUID { profile.id }
}
