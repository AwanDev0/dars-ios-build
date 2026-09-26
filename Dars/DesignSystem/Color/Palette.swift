import SwiftUI

struct DarsPalette: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let note: String
    let darkBg: UInt32, darkCard: UInt32, darkCardAlt: UInt32, darkRaised: UInt32
    let lightBg: UInt32, lightCardAlt: UInt32
    let accentDark: UInt32, accentLight: UInt32, accentTextLight: UInt32
    let onAccentDark: UInt32, onAccentLight: UInt32
    let actionDark: UInt32, actionLight: UInt32

    var id: String { key }
    var isBrand: Bool { key == "gold" }

    static func of(_ key: String?) -> DarsPalette { all.first { $0.key == key } ?? gold }
    static var gold: DarsPalette { all[0] }

    static let all: [DarsPalette] = [
        DarsPalette(key: "gold", name: "Gold", note: "The brand. Near-black and ivory, gold on both, the dinner-jacket navy for the button.",
            darkBg: 0x09090F, darkCard: 0x16161F, darkCardAlt: 0x1D1D26, darkRaised: 0x26262F,
            lightBg: 0xF7F5F2, lightCardAlt: 0xFAFAFB,
            accentDark: 0xFAB900, accentLight: 0xFAB900, accentTextLight: 0x8F6A00,
            onAccentDark: 0x09090F, onAccentLight: 0x09090F,
            actionDark: 0x232B3E, actionLight: 0x0F172A),
        DarsPalette(key: "champagne", name: "Champagne", note: "Midnight and champagne: the navy of a dinner jacket, champagne for the ten.",
            darkBg: 0x060915, darkCard: 0x0D1229, darkCardAlt: 0x171E3B, darkRaised: 0x202849,
            lightBg: 0xF7F4EC, lightCardAlt: 0xFCFAF5,
            accentDark: 0xF1D9A6, accentLight: 0xD4B26A, accentTextLight: 0x7A5A16,
            onAccentDark: 0x141006, onAccentLight: 0x1E1606,
            actionDark: 0x1C2752, actionLight: 0x13203F),
        DarsPalette(key: "emerald", name: "Emerald", note: "Emerald and brass: a deep green ground, brass for the ten, the emerald for the button.",
            darkBg: 0x040E0A, darkCard: 0x0B1813, darkCardAlt: 0x162922, darkRaised: 0x1A2F27,
            lightBg: 0xF1F6F2, lightCardAlt: 0xF7FAF8,
            accentDark: 0xD4AF37, accentLight: 0xB8962E, accentTextLight: 0x6E5A12,
            onAccentDark: 0x141004, onAccentLight: 0x1E1606,
            actionDark: 0x0F4A36, actionLight: 0x0B3B2B),
        DarsPalette(key: "bordeaux", name: "Bordeaux", note: "Bordeaux and blush gold: a wine-dark ground, blush gold for the ten, the wine for the button.",
            darkBg: 0x120609, darkCard: 0x1F0F14, darkCardAlt: 0x28151B, darkRaised: 0x331C23,
            lightBg: 0xFAF2F1, lightCardAlt: 0xFDF8F7,
            accentDark: 0xE9C39B, accentLight: 0xC99A6B, accentTextLight: 0x7A4B22,
            onAccentDark: 0x1A1008, onAccentLight: 0x241406,
            actionDark: 0x5A1626, actionLight: 0x4A0F1E),
        DarsPalette(key: "noir", name: "Noir", note: "Black and pearl: true black, pearl for the ten, graphite for the button. Colour is the one thing it refuses.",
            darkBg: 0x000000, darkCard: 0x121212, darkCardAlt: 0x1A1A1A, darkRaised: 0x242424,
            lightBg: 0xF5F5F5, lightCardAlt: 0xFAFAFA,
            accentDark: 0xEDE9E3, accentLight: 0x3A3A3C, accentTextLight: 0x3A3A3C,
            onAccentDark: 0x111111, onAccentLight: 0xFFFFFF,
            actionDark: 0x2C2C2E, actionLight: 0x1C1C1E),
        DarsPalette(key: "rosegold", name: "Rose gold", note: "Obsidian and rose gold, a wine button.",
            darkBg: 0x0B0809, darkCard: 0x181214, darkCardAlt: 0x20191B, darkRaised: 0x2A2124,
            lightBg: 0xFAF3F1, lightCardAlt: 0xFDF9F8,
            accentDark: 0xE8B4A6, accentLight: 0xCF8E7C, accentTextLight: 0x9A4A3A,
            onAccentDark: 0x1A0F0D, onAccentLight: 0x2A120B,
            actionDark: 0x4A1F2B, actionLight: 0x3A1521),
        DarsPalette(key: "copper", name: "Copper", note: "Espresso and copper, the espresso itself for the button.",
            darkBg: 0x0F0A08, darkCard: 0x1B1411, darkCardAlt: 0x231B17, darkRaised: 0x2D231E,
            lightBg: 0xF8F3EE, lightCardAlt: 0xFCF9F6,
            accentDark: 0xD98C5F, accentLight: 0xC4763F, accentTextLight: 0x8A4A22,
            onAccentDark: 0x1A0E08, onAccentLight: 0x2A1408,
            actionDark: 0x3E2418, actionLight: 0x2F1A10),
        DarsPalette(key: "vanilla", name: "Vanilla", note: "Cosmic purple and vanilla, a violet button.",
            darkBg: 0x0A0719, darkCard: 0x14102C, darkCardAlt: 0x1E1A3E, darkRaised: 0x28224D,
            lightBg: 0xFBF8F1, lightCardAlt: 0xFEFCF7,
            accentDark: 0xF3E5AB, accentLight: 0xD6B65A, accentTextLight: 0x7A5F14,
            onAccentDark: 0x14102A, onAccentLight: 0x1E1508,
            actionDark: 0x302662, actionLight: 0x251C55),
        DarsPalette(key: "cream", name: "Cream", note: "Forest and cream, a moss button.",
            darkBg: 0x080D0A, darkCard: 0x0F1813, darkCardAlt: 0x18221C, darkRaised: 0x202C25,
            lightBg: 0xF6F3EA, lightCardAlt: 0xFBF9F3,
            accentDark: 0xF3E9C8, accentLight: 0xD1B96E, accentTextLight: 0x6B5A1E,
            onAccentDark: 0x12130A, onAccentLight: 0x1E1806,
            actionDark: 0x1F3B2B, actionLight: 0x153020),
        DarsPalette(key: "orchid", name: "Orchid", note: "Jet black and orchid, aubergine for the button.",
            darkBg: 0x070707, darkCard: 0x151216, darkCardAlt: 0x1C181D, darkRaised: 0x262029,
            lightBg: 0xF9F4F9, lightCardAlt: 0xFCF8FC,
            accentDark: 0xDA70D6, accentLight: 0xAE38A8, accentTextLight: 0x8E2E88,
            onAccentDark: 0x0B0B0B, onAccentLight: 0xFFFFFF,
            actionDark: 0x3E1F3C, actionLight: 0x2C1030),
        DarsPalette(key: "violet", name: "Violet", note: "Indigo night and violet, deep indigo for the button.",
            darkBg: 0x0B0917, darkCard: 0x151227, darkCardAlt: 0x211D3C, darkRaised: 0x2B2649,
            lightBg: 0xF4F1FA, lightCardAlt: 0xF9F7FD,
            accentDark: 0x9D7BFF, accentLight: 0x6D45E8, accentTextLight: 0x5B36C7,
            onAccentDark: 0x0E0A1F, onAccentLight: 0xFFFFFF,
            actionDark: 0x2E2560, actionLight: 0x1F1650),
        DarsPalette(key: "candy", name: "Candy blue", note: "Onyx and a sky blue, deep navy for the button.",
            darkBg: 0x0A0C11, darkCard: 0x12181F, darkCardAlt: 0x1B222C, darkRaised: 0x232B37,
            lightBg: 0xF2F5F8, lightCardAlt: 0xF8FAFC,
            accentDark: 0x38BDF8, accentLight: 0x0EA5E9, accentTextLight: 0x0369A1,
            onAccentDark: 0x071018, onAccentLight: 0x06202E,
            actionDark: 0x1C2B45, actionLight: 0x10203A),
        DarsPalette(key: "turquoise", name: "Turquoise", note: "Warm ash and turquoise, deep teal for the button.",
            darkBg: 0x100E0D, darkCard: 0x1B1615, darkCardAlt: 0x282221, darkRaised: 0x322A29,
            lightBg: 0xF6F1EF, lightCardAlt: 0xFBF8F7,
            accentDark: 0x2DD4BF, accentLight: 0x14B8A6, accentTextLight: 0x0F766E,
            onAccentDark: 0x0B1514, onAccentLight: 0x06201C,
            actionDark: 0x163F3B, actionLight: 0x0F3532),
        DarsPalette(key: "mint", name: "Mint", note: "Slate and mint, a pine button.",
            darkBg: 0x0A0F12, darkCard: 0x12181D, darkCardAlt: 0x1C242A, darkRaised: 0x242D34,
            lightBg: 0xF1F6F4, lightCardAlt: 0xF7FAF9,
            accentDark: 0x9EEBC8, accentLight: 0x4FCB9A, accentTextLight: 0x0F6B4B,
            onAccentDark: 0x08150F, onAccentLight: 0x06201A,
            actionDark: 0x1B3B35, actionLight: 0x12302A),
        DarsPalette(key: "lime", name: "Lime", note: "Carbon and lime, a forest button.",
            darkBg: 0x0A0D0A, darkCard: 0x121812, darkCardAlt: 0x1B221B, darkRaised: 0x242C24,
            lightBg: 0xF4F7F1, lightCardAlt: 0xF9FBF6,
            accentDark: 0xA3E635, accentLight: 0x84CC16, accentTextLight: 0x3F6A0A,
            onAccentDark: 0x0B120B, onAccentLight: 0x0D1A04,
            actionDark: 0x1F3B23, actionLight: 0x16301B),
        DarsPalette(key: "coral", name: "Coral", note: "Ink and coral, deep ink for the button.",
            darkBg: 0x0A0C15, darkCard: 0x121625, darkCardAlt: 0x1B2034, darkRaised: 0x242942,
            lightBg: 0xF8F4F2, lightCardAlt: 0xFCF9F8,
            accentDark: 0xFF7F6E, accentLight: 0xF0654F, accentTextLight: 0xB43E2C,
            onAccentDark: 0x1A0C0A, onAccentLight: 0x2A0E08,
            actionDark: 0x252C4C, actionLight: 0x171D3B),
        DarsPalette(key: "peach", name: "Peach", note: "Plum and peach, a plum button.",
            darkBg: 0x10060D, darkCard: 0x1C1017, darkCardAlt: 0x271821, darkRaised: 0x32202B,
            lightBg: 0xFBF4F1, lightCardAlt: 0xFEFAF8,
            accentDark: 0xFFC4A3, accentLight: 0xF29B6B, accentTextLight: 0x9C4A24,
            onAccentDark: 0x1C0E08, onAccentLight: 0x2A1408,
            actionDark: 0x4B1E3B, actionLight: 0x3B1330),
        DarsPalette(key: "ice", name: "Ice", note: "Graphite and ice, a slate button.",
            darkBg: 0x0B0D11, darkCard: 0x13161C, darkCardAlt: 0x1E222A, darkRaised: 0x262B35,
            lightBg: 0xF3F5F8, lightCardAlt: 0xF8FAFC,
            accentDark: 0xBFE3F6, accentLight: 0x7CC0E4, accentTextLight: 0x0E5C80,
            onAccentDark: 0x0A1720, onAccentLight: 0x07202E,
            actionDark: 0x2B3546, actionLight: 0x1C2634),
    ]
}

@Observable
final class PaletteStore {
    nonisolated(unsafe) static let shared = PaletteStore()
    private static let storageKey = "dars.palette"

    private(set) var current: DarsPalette

    private init() {
        current = DarsPalette.of(UserDefaults.standard.string(forKey: Self.storageKey))
    }

    func set(_ palette: DarsPalette) {
        guard palette != current else { return }
        current = palette
        UserDefaults.standard.set(palette.key, forKey: Self.storageKey)
    }
}
