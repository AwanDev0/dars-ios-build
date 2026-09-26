import SwiftUI

struct CardList<Content: View>: View {
    var inset: CGFloat = Metrics.Space.md
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionLabel: View {
    let text: LocalizedStringKey
    var trailing: String?
    init(_ text: LocalizedStringKey, trailing: String? = nil) { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack {
            Text(text).darsType(.caption).textCase(.uppercase).kerning(0.6).foregroundStyle(DarsColor.labelTertiary)
            Spacer()
            if let trailing { Text(trailing).darsType(.caption).foregroundStyle(DarsColor.labelTertiary) }
        }
        .padding(.horizontal, 4)
    }
}

struct EmptyCard: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).darsType(.subheadline).foregroundStyle(DarsColor.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(Metrics.Space.md)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    var symbol: String? = nil
    var tint: Color = DarsColor.accentLabel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint) }
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(DarsColor.labelPrimary).contentTransition(.numericText())
            Text(label).darsType(.caption).foregroundStyle(DarsColor.labelSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.Space.md)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LinkRow: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    var symbol: String? = nil
    var tint: Color = DarsColor.accentLabel
    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 32, height: 32).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).darsType(.headline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                if let detail { Text(detail).darsType(.caption).foregroundStyle(DarsColor.labelTertiary).lineLimit(2) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DarsColor.labelTertiary)
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct PersonLine<Trailing: View>: View {
    let profile: Profile
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing
    @Environment(LanguageStore.self) private var language

    init(_ profile: Profile, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.profile = profile; self.detail = detail; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: profile.avatarURL, initials: profile.avatarInitials ?? String(profile.fullName.prefix(1)), color: profile.avatarColor, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName(kurdish: language.language.isKurdish)).darsType(.headline).foregroundStyle(DarsColor.labelPrimary).lineLimit(1)
                if let detail, !detail.isEmpty { Text(detail).darsType(.caption).foregroundStyle(DarsColor.labelTertiary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Metrics.Space.md).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

extension PersonLine where Trailing == EmptyView {
    init(_ profile: Profile, detail: String? = nil) {
        self.init(profile, detail: detail) { EmptyView() }
    }
}

struct RowDivider: View {
    var inset: CGFloat = 68
    var body: some View { Divider().padding(.leading, inset) }
}

struct DarsField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .padding(.horizontal, 14).frame(height: 50)
            .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DarsColor.separator, lineWidth: 0.5))
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey = "Search"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DarsColor.labelTertiary)
            TextField(prompt, text: $text).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DarsColor.labelTertiary) }
            }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(DarsColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ScreenTitle: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).darsType(.largeTitle).foregroundStyle(DarsColor.labelPrimary)
            if let subtitle { Text(subtitle).darsType(.subheadline).foregroundStyle(DarsColor.labelSecondary) }
        }
    }
}

struct ChipRow<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selected: T
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    let on = item.0 == selected
                    Button {
                        HapticEngine.play(.selection)
                        withAnimation(Motion.selection) { selected = item.0 }
                    } label: {
                        Text(item.1).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? DarsColor.onAccent : DarsColor.labelPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? DarsColor.accent : DarsColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

extension AttendanceStatus {
    var color: Color {
        switch self {
        case .present: return DarsColor.success
        case .absent: return DarsColor.danger
        case .late: return DarsColor.warning
        case .excused: return Color(hex: 0x5856D6)
        }
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
}
