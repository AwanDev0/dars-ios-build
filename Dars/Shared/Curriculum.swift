import SwiftUI

enum Curriculum {
    static let grade10and11 = [
        "Kurdish", "Arabic", "English", "Mathematics", "Physics", "Chemistry",
        "Biology", "Islamic Education", "IT", "Art", "Rights / Genocide", "PE",
    ]

    static let grade12 = [
        "Kurdish", "Arabic", "English", "Mathematics", "Physics", "Chemistry",
        "Biology", "Islamic Education", "PE",
    ]

    static func forGrade(_ grade: String?) -> [String] {
        switch grade?.trimmingCharacters(in: .whitespaces) {
        case "12": return grade12
        default: return grade10and11
        }
    }

    static var all: [String] {
        var seen = Set<String>()
        return (grade10and11 + grade12).filter { seen.insert($0).inserted }
    }
}

enum SubjectName {
    private static let kurdish: [String: String] = [
        "Kurdish": "کوردی",
        "Arabic": "عەرەبی",
        "English": "ئینگلیزی",
        "Mathematics": "بیرکاری",
        "Maths": "بیرکاری",
        "Math": "بیرکاری",
        "Physics": "فیزیا",
        "Chemistry": "کیمیا",
        "Biology": "بایۆلۆجی",
        "Islamic Education": "پەروەردەی ئیسلامی",
        "IT": "کۆمپیوتەر",
        "Computer Science": "کۆمپیوتەر",
        "Computer": "کۆمپیوتەر",
        "Art": "هونەر",
        "Rights / Genocide": "ماف / جینۆساید",
        "Rights": "ماف",
        "PE": "پەروەردەی وەرزشی",
        "Physical Education": "پەروەردەی وەرزشی",
        "Sport": "پەروەردەی وەرزشی",
        "Break": "پشوو",
    ]

    static func label(_ subject: String?, kurdish isKurdish: Bool) -> String {
        guard let subject = subject?.trimmingCharacters(in: .whitespaces), !subject.isEmpty else { return "" }
        guard isKurdish else { return subject }
        return kurdish[subject] ?? subject
    }

    static func short(_ subject: String?, kurdish isKurdish: Bool) -> String {
        guard let subject = subject?.trimmingCharacters(in: .whitespaces), !subject.isEmpty else { return "" }
        if isKurdish { return label(subject, kurdish: true) }
        switch subject {
        case "Mathematics", "Math": return "Maths"
        case "Islamic Education": return "Islamic"
        case "Rights / Genocide": return "Rights"
        case "Chemistry": return "Chem."
        default: return subject
        }
    }

    static func symbol(_ subject: String?) -> String {
        switch subject?.trimmingCharacters(in: .whitespaces) {
        case "Mathematics", "Maths", "Math": return "function"
        case "Physics": return "atom"
        case "Chemistry": return "flask.fill"
        case "Biology": return "leaf.fill"
        case "English": return "textformat.abc"
        case "Kurdish", "Arabic": return "character.book.closed.fill"
        case "Islamic Education": return "book.closed.fill"
        case "IT", "Computer", "Computer Science": return "desktopcomputer"
        case "Art": return "paintpalette.fill"
        case "PE", "Physical Education", "Sport": return "figure.run"
        case "Rights / Genocide", "Rights": return "scalemass.fill"
        default: return "book.fill"
        }
    }
}

enum DayName {
    static let keys = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let englishFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let kurdishFull = ["یەکشەم", "دووشەم", "سێشەم", "چوارشەم", "پێنجشەم", "هەینی", "شەممە"]
    private static let kurdishShort = ["یەک", "دوو", "سێ", "چوار", "پێنج", "هەینی", "شەممە"]

    static func full(_ key: String, kurdish: Bool) -> String {
        guard let i = keys.firstIndex(of: key) else { return key }
        return kurdish ? kurdishFull[i] : englishFull[i]
    }

    static func short(_ key: String, kurdish: Bool) -> String {
        guard let i = keys.firstIndex(of: key) else { return key }
        return kurdish ? kurdishShort[i] : key
    }
}

struct SubjectText: View {
    let subject: String?
    var short = false
    @Environment(LanguageStore.self) private var language

    var body: some View {
        Text(verbatim: short
             ? SubjectName.short(subject, kurdish: language.language.isKurdish)
             : SubjectName.label(subject, kurdish: language.language.isKurdish))
    }
}

struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func hidesDarsTabBar() -> some View { preference(key: HidesTabBarKey.self, value: true) }
}
