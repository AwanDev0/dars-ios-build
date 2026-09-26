import SwiftUI

struct DarsTabItem: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let icon: String
    let iconOutline: String
    var isPost = false
    var title: String { L(titleKey) }
}

struct DarsTabBar: View {
    let tabs: [DarsTabItem]
    let selected: String
    let onSelect: (DarsTabItem) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var ghost: String?
    @State private var stretch: CGFloat = 1
    @State private var squash: CGFloat = 1
    @State private var labelWidths: [String: CGFloat] = [:]

    private let capsuleHeight: CGFloat = 56
    private let ghostSpring = Motion.spring(damping: 0.9, stiffness: 140)

    private var places: [DarsTabItem] { tabs.filter { !$0.isPost } }
    private var post: DarsTabItem? { tabs.first { $0.isPost } }

    var body: some View {
        HStack(spacing: 10) {
            capsule
            if let post {
                PostDisc(tab: post) { onSelect(post) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: [.clear, Tokens.bg.opacity(0.92), Tokens.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .background(alignment: .topLeading) { measurer }
        .onAppear { ghost = selected }
        .onChange(of: selected) { _, now in
            guard places.contains(where: { $0.id == now }) else { return }
            if reduce {
                ghost = now
                return
            }
            withAnimation(ghostSpring) { ghost = now }
            withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: 0.08), completionCriteria: .logicallyComplete) {
                stretch = 1.10
                squash = 0.86
            } completion: {
                withAnimation(Motion.tab, completionCriteria: .logicallyComplete) {
                    stretch = 1
                    squash = 1.04
                } completion: {
                    withAnimation(Motion.tab) { squash = 1 }
                }
            }
        }
    }

    private var measurer: some View {
        ZStack {
            ForEach(places) { tab in
                Text(verbatim: tab.title)
                    .font(.system(size: 12.5, weight: .bold))
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidths[tab.id] = $0 }
            }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func widths(inner: CGFloat, selectedIndex: Int) -> [CGFloat] {
        let n = places.count
        guard n > 0, inner > 0 else { return Array(repeating: 0, count: n) }
        guard n > 1 else { return [inner] }
        let unit = inner / (CGFloat(n - 1) + 1.85)
        let label = labelWidths[places[max(0, min(selectedIndex, n - 1))].id] ?? 0
        let needed = 34 + 6 + label + 2 + 14
        let wide = min(max(unit * 1.85, needed), inner - CGFloat(n - 1) * 40)
        let rest = (inner - wide) / CGFloat(n - 1)
        return (0..<n).map { $0 == selectedIndex ? wide : rest }
    }

    private func rect(of index: Int, inner: CGFloat) -> (x: CGFloat, w: CGFloat) {
        let w = widths(inner: inner, selectedIndex: index)
        guard index >= 0, index < w.count else { return (0, 0) }
        let left = w[0..<index].reduce(0, +)
        let x = direction == .rightToLeft ? inner - left - w[index] : left
        return (x, w[index])
    }

    private var capsule: some View {
        GeometryReader { g in
            let inner = g.size.width - 8
            let selectedIndex = places.firstIndex { $0.id == selected } ?? -1
            let slotWidths = widths(inner: inner, selectedIndex: selectedIndex)
            let pill = rect(of: selectedIndex, inner: inner)
            let ghostRect = rect(of: places.firstIndex { $0.id == (ghost ?? selected) } ?? selectedIndex, inner: inner)
            ZStack(alignment: .topLeading) {
                if selectedIndex >= 0 {
                    if !reduce {
                        Capsule()
                            .fill(Tokens.accent)
                            .opacity(0.38)
                            .frame(width: ghostRect.w, height: capsuleHeight - 8)
                            .offset(x: ghostRect.x)
                    }
                    Capsule()
                        .fill(Tokens.accent)
                        .frame(width: pill.w, height: capsuleHeight - 8)
                        .scaleEffect(x: stretch, y: squash)
                        .offset(x: pill.x)
                }
                HStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { _, tab in
                        let i = places.firstIndex(of: tab) ?? 0
                        TabSlot(tab: tab, selected: tab.id == selected, direction: direction) { onSelect(tab) }
                            .frame(width: i < slotWidths.count ? slotWidths[i] : 0, height: capsuleHeight - 8)
                    }
                }
            }
            .padding(4)
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(height: capsuleHeight)
        .background(Tokens.card.opacity(scheme == .dark ? 0.94 : 0.96), in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.16 : 0.9), Tokens.border.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.20), radius: 16, x: 0, y: 8)
    }

    private var ordered: [DarsTabItem] { direction == .rightToLeft ? places.reversed() : places }
}

private struct TabSlot: View {
    let tab: DarsTabItem
    let selected: Bool
    let direction: LayoutDirection
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var halo: CGFloat = 1
    @State private var pop: CGFloat = 1
    @State private var hop: CGFloat = 0

    var body: some View {
        let inactive = scheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.50)
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    HaloRing(progress: halo)
                    ZStack {
                        MaterialIcon(tab.iconOutline, size: 22).opacity(selected ? 0 : 1)
                        MaterialIcon(tab.icon, size: 22).opacity(selected ? 1 : 0)
                    }
                    .foregroundStyle(selected ? Tokens.onAccent : inactive)
                    .animation(Motion.standard, value: selected)
                    .scaleEffect(pop)
                    .offset(y: hop * 3)
                }
                .frame(width: 34, height: 34)
                if selected {
                    Text(verbatim: tab.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Tokens.onAccent)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 6)
                        .padding(.trailing, 2)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Motion.emphasis).combined(with: .scale(scale: 0.4, anchor: .leading)),
                            removal: .opacity.animation(Motion.instant)
                        ))
                }
            }
            .environment(\.layoutDirection, direction)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle(active: !selected))
        .accessibilityLabel(Text(verbatim: tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: selected) { _, now in
            guard now, !reduce else { return }
            halo = 0
            withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.52)) { halo = 1 }
            withAnimation(Motion.micro, completionCriteria: .logicallyComplete) { pop = 1.16 } completion: {
                withAnimation(Motion.micro) { pop = 1 }
            }
            withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.11), completionCriteria: .logicallyComplete) { hop = -1 } completion: {
                withAnimation(Motion.micro) { hop = 0 }
            }
        }
    }
}

private struct HaloRing: View, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = progress
        let alpha: CGFloat = p >= 1 ? 0 : (p < 0.12 ? p / 0.12 * 0.4 : (1 - (p - 0.12) / 0.88) * 0.4)
        Circle()
            .stroke(Tokens.accent, lineWidth: 1.5)
            .frame(width: 34, height: 34)
            .scaleEffect(0.7 + p)
            .opacity(alpha)
            .allowsHitTesting(false)
    }
}

private struct TabPressStyle: ButtonStyle {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && active && !reduce ? 0.90 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

private struct PostDisc: View {
    let tab: DarsTabItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaterialIcon(tab.icon, size: 24)
                .foregroundStyle(Tokens.onAccent)
                .frame(width: 56, height: 56)
                .background(Tokens.accent, in: Circle())
                .shadow(color: Tokens.accent.opacity(0.35), radius: 12, x: 0, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(TabPressStyle(active: true))
        .accessibilityLabel(Text(verbatim: tab.title))
    }
}

struct OpenTabAction {
    let open: (String) -> Void
    func callAsFunction(_ id: String) { open(id) }
}

private struct OpenTabKey: EnvironmentKey {
    static let defaultValue = OpenTabAction { _ in }
}

extension EnvironmentValues {
    var openTab: OpenTabAction {
        get { self[OpenTabKey.self] }
        set { self[OpenTabKey.self] = newValue }
    }
}
