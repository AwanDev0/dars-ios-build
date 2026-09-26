import Foundation

enum Role: String, Codable, Sendable, CaseIterable {
    case student
    case teacher
    case parent
    case admin

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Role(rawValue: raw) ?? .student
    }
}

struct Profile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let fullName: String
    let role: Role
    let schoolId: UUID?
    let grade: String?
    let section: String?
    let subject: String?
    let avatarURL: String?
    let avatarColor: String?
    let avatarInitials: String?

    let fullNameKu: String?

    let suspendedAt: String?

    func displayName(kurdish: Bool) -> String {
        if kurdish, let ku = fullNameKu, !ku.isEmpty { return ku }
        return fullName
    }

    var classLabel: String? {
        guard let grade, let section else { return nil }
        return grade + section
    }

    static let columns = """
        id, full_name, role, school_id, grade, section, subject, \
        avatar_url, avatar_color, avatar_initials, full_name_ku, suspended_at
        """

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case role
        case schoolId = "school_id"
        case grade
        case section
        case subject
        case avatarURL = "avatar_url"
        case avatarColor = "avatar_color"
        case avatarInitials = "avatar_initials"
        case fullNameKu = "full_name_ku"
        case suspendedAt = "suspended_at"
    }

    var isSuspended: Bool { suspendedAt != nil }
}

struct School: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let nameKu: String?
    let code: String
    let currentSemester: String

    func displayName(kurdish: Bool) -> String {
        if kurdish, let ku = nameKu, !ku.isEmpty { return ku }
        return name
    }

    static let columns = "id, name, name_ku, code, current_semester"

    enum CodingKeys: String, CodingKey {
        case id, name, code
        case nameKu = "name_ku"
        case currentSemester = "current_semester"
    }
}

struct SchoolClass: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let grade: String
    let section: String
    let schoolId: UUID?

    var label: String { grade + section }

    static let columns = "id, name, grade, section, school_id"

    enum CodingKeys: String, CodingKey {
        case id, name, grade, section
        case schoolId = "school_id"
    }
}
