import Foundation

enum Lang {
    nonisolated(unsafe) static var current: AppLanguage = .english
    nonisolated(unsafe) private static var bundles: [String: Bundle] = [:]
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func bundle(_ language: AppLanguage) -> Bundle {
        if let cached = bundles[language.rawValue] { return cached }
        let found = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap { Bundle(path: $0) } ?? .main
        bundles[language.rawValue] = found
        return found
    }

    static func raw(_ key: String) -> String {
        let full = "a." + key
        let value = bundle(current).localizedString(forKey: full, value: nil, table: nil)
        if value != full { return value }
        let english = bundle(.english).localizedString(forKey: full, value: nil, table: nil)
        return english == full ? key : english
    }

    static func format(_ template: String, _ args: [CVarArg]) -> String {
        args.isEmpty ? template : String(format: template, locale: posix, arguments: args)
    }
}

func L(_ key: String, _ args: CVarArg...) -> String {
    Lang.format(Lang.raw(key), args)
}

func P(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
    let form = Lang.raw("\(key)#\(count == 1 ? "one" : "other")")
    return Lang.format(form, args.isEmpty ? [count] : args)
}
