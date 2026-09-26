import SwiftUI

struct DarsTab: Identifiable, Equatable, Hashable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    let selectedSymbol: String

    static func == (a: DarsTab, b: DarsTab) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct CapsuleTabBar: View {
    let tabs: [DarsTab]
    @Binding var selected: String
    @Namespace private var pill

    private var compact: Bool { tabs.count > 5 }

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(tabs) { tab in
                let on = tab.id == selected
                Button {
                    guard !on else { return }
                    HapticEngine.play(.selection)
                    withAnimation(Motion.arrive) { selected = tab.id }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on ? tab.selectedSymbol : tab.symbol)
                            .font(.system(size: compact ? 18 : 20, weight: .medium))
                            .symbolEffect(.bounce, value: on)
                        if on {
                            Text(tab.title)
                                .font(.system(size: compact ? 11.5 : 12.5, weight: .bold))
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundStyle(on ? Color.black : DarsColor.labelSecondary)
                    .padding(.horizontal, on ? (compact ? 10 : 14) : (compact ? 7 : 10))
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 46 : 48)
                    .background {
                        if on {
                            Capsule()
                                .fill(DarsColor.brandGold)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .layoutPriority(on ? 1 : 0)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(4)
        .background { capsuleGlass }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var capsuleGlass: some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(DarsColor.glassStroke, lineWidth: 1))
        }
    }
}

struct SidebarTabs: View {
    let tabs: [DarsTab]
    @Binding var selected: String

    var body: some View {
        List(selection: Binding(get: { Optional(selected) }, set: { if let v = $0 { selected = v } })) {
            ForEach(tabs) { tab in
                Label(tab.title, systemImage: tab.id == selected ? tab.selectedSymbol : tab.symbol)
                    .tag(tab.id)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Dars")
        .tint(DarsColor.accent)
    }
}
