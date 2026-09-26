import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case sorani = "ckb"

    var id: String { rawValue }

    var endonym: String {
        switch self {
        case .english: return "English"
        case .sorani: return "کوردی"
        }
    }

    var script: DarsType.Script {
        self == .sorani ? .arabic : .latin
    }

    var layoutDirection: LayoutDirection {
        self == .sorani ? .rightToLeft : .leftToRight
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var isKurdish: Bool { self == .sorani }
}

@MainActor
@Observable
final class LanguageStore {
    private static let storageKey = "dars.language"

    private(set) var language: AppLanguage

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.storageKey),
           let restored = AppLanguage(rawValue: saved) {
            language = restored
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            language = preferred.hasPrefix("ckb") ? .sorani : .english
        }
    }

    func set(_ new: AppLanguage) {
        guard new != language else { return }
        language = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.storageKey)
    }

    func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: language.locale)
    }
}

extension View {
    func darsLanguage(_ language: AppLanguage) -> some View {
        self
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            .darsScript(language.script)
    }
}
