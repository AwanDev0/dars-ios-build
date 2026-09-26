import SwiftUI

func RR(_ radius: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .circular) }

enum MaterialLevel { case card, raised, sheet }

private struct DarsMaterialModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let level: MaterialLevel
    let fill: Color?
    let rim: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let elevation: CGFloat
        switch level {
        case .card: elevation = dark ? 3 : 2
        case .raised: elevation = dark ? 8 : 5
        case .sheet: elevation = dark ? 16 : 12
        }
        let surface = fill ?? (level == .card ? Tokens.card : Tokens.raised)
        return content
            .background(shape.fill(surface))
            .clipShape(shape)
            .overlay { if rim { shape.strokeBorder(Tokens.border, lineWidth: 1) } }
            .shadow(color: Color(hex: 0x0B0B12).opacity(dark ? 0.35 : 0.10), radius: elevation * 0.9, x: 0, y: elevation * 0.55)
    }
}

extension View {
    func darsMaterial<S: InsettableShape>(_ shape: S, level: MaterialLevel = .card, fill: Color? = nil, rim: Bool = true) -> some View {
        modifier(DarsMaterialModifier(shape: shape, level: level, fill: fill, rim: rim))
    }

    func darsGround() -> some View { modifier(DarsGround()) }

    func glassTile<S: InsettableShape>(_ tint: Color, shape: S) -> some View { modifier(GlassTile(tint: tint, shape: shape)) }

    func darsEnter(delay: Double = 0, rise: CGFloat = 14) -> some View { modifier(DarsEnter(delay: delay, rise: rise)) }

    func darsStagger(_ index: Int, step: Double = 0.07, delay: Double = 0.06, rise: CGFloat = 14) -> some View {
        modifier(DarsEnter(delay: delay + Double(index) * step, rise: rise))
    }

    func darsTracking(_ value: CGFloat) -> some View { modifier(DarsTracking(value: value)) }
}

private struct DarsTracking: ViewModifier {
    let value: CGFloat
    @Environment(\.darsScript) private var script
    func body(content: Content) -> some View { content.tracking(script == .arabic ? 0 : value) }
}

private struct DarsGround: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Tokens.bg
                LinearGradient(
                    colors: [scheme == .dark ? Color.white.opacity(0.020) : Color.black.opacity(0.014), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }
}

private struct GlassTile<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        return content
            .background {
                ZStack {
                    shape.fill(tint.opacity(dark ? 0.16 : 0.11))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.14 : 0.30), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(tint.opacity(0.35), lineWidth: 1) }
            .overlay(alignment: .top) {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.white.opacity(dark ? 0.28 : 0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.56, height: 1)
                        .offset(x: g.size.width * 0.22, y: 0.5)
                }
                .allowsHitTesting(false)
            }
    }
}

private struct DarsEnter: ViewModifier {
    let delay: Double
    let rise: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : rise)
            .onAppear {
                guard !shown, !reduce else { return }
                withAnimation(Motion.arrive.delay(delay)) { shown = true }
            }
    }
}

struct DarsPress: ButtonStyle {
    var scale: CGFloat = Motion.Scale.row
    var radius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        PressLabel(configuration: configuration, scale: scale, radius: radius)
    }

    private struct PressLabel: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        let radius: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduce

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .overlay {
                    RR(radius)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                        .opacity(pressed && !reduce ? 1 : 0)
                        .animation(pressed ? .timingCurve(0, 0, 0.2, 1, duration: 0.09) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.26), value: pressed)
                        .allowsHitTesting(false)
                }
                .scaleEffect(pressed && !reduce ? scale : 1)
                .opacity(pressed && reduce ? 0.72 : 1)
                .animation(Motion.press, value: pressed)
        }
    }
}

struct MotionCard<Content: View>: View {
    var radius: CGFloat = 16
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if let action {
            Button {
                HapticEngine.play(.selection)
                action()
            } label: { surface }
            .buttonStyle(DarsPress(scale: Motion.Scale.card, radius: radius))
        } else {
            surface
        }
    }

    private var surface: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.card, in: RR(radius))
            .overlay(RR(radius).strokeBorder(Tokens.border, lineWidth: 1))
            .contentShape(RR(radius))
    }
}

struct MotionRow<Content: View>: View {
    var action: () -> Void
    var fill: Color = .clear
    @ViewBuilder var content: Content

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            content
                .frame(maxWidth: .infinity, minHeight: Motion.minTouchTarget, alignment: .leading)
                .background(fill)
                .contentShape(Rectangle())
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.row))
    }
}

struct MotionChip: View {
    let text: String
    let selected: Bool
    var radius: CGFloat = 20
    var horizontal: CGFloat = 18
    var vertical: CGFloat = 8
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var pop: CGFloat = 1

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            Text(verbatim: text)
                .font(.system(size: 13, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? Tokens.onAccent : Tokens.textSub)
                .lineLimit(1)
                .padding(.horizontal, horizontal)
                .padding(.vertical, vertical)
                .frame(minHeight: Motion.minTouchTarget)
                .background(selected ? Tokens.accent : Tokens.card, in: RR(radius))
                .overlay(RR(radius).strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: 0.8))
                .animation(Motion.standard, value: selected)
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.chip, radius: radius))
        .scaleEffect(pop)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: selected) { was, now in
            guard now, !was, !reduce else { return }
            withAnimation(Motion.spring(damping: 0.37, stiffness: 600), completionCriteria: .logicallyComplete) {
                pop = 1.05
            } completion: {
                withAnimation(Motion.micro) { pop = 1 }
            }
        }
    }
}

enum ButtonPhase { case idle, working, done }

struct MotionPrimaryButton: View {
    let title: LocalizedStringKey
    var enabled = true
    var loading = false
    var done = false
    var doneTitle: LocalizedStringKey? = nil
    var radius: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.play(.impactLight)
            action()
        } label: {
            ZStack {
                if done {
                    HStack(spacing: 6) {
                        MaterialIcon("Filled.Check", size: 18)
                        Text(doneTitle ?? title).font(.system(size: 16, weight: .semibold))
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                } else {
                    Text(title).font(.system(size: 16, weight: .semibold)).opacity(loading ? 0 : 1)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                    if loading { ProgressView().tint(Tokens.onAccent).controlSize(.regular) }
                }
            }
            .foregroundStyle(Tokens.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Tokens.accent, in: RR(radius))
            .contentShape(RR(radius))
            .animation(Motion.emphasis, value: done)
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.primary, radius: radius))
        .opacity(enabled || loading || done ? 1 : 0.45)
        .animation(Motion.standard, value: enabled)
        .disabled(!enabled || loading || done)
        .onChange(of: done) { _, now in if now { HapticEngine.play(.success) } }
    }
}

struct MotionButton: View {
    let title: LocalizedStringKey
    var enabled = true
    var destructive = false
    var phase: ButtonPhase = .idle
    var doneTitle: LocalizedStringKey? = nil
    var radius: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.play(destructive ? .warning : .selection)
            action()
        } label: {
            ZStack {
                if phase == .done {
                    HStack(spacing: 6) {
                        MaterialIcon("Filled.Check", size: 18)
                        Text(doneTitle ?? title).font(.system(size: 15, weight: .medium))
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                } else {
                    Text(title).font(.system(size: 15, weight: .medium))
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .foregroundStyle(destructive ? Tokens.danger : Tokens.text)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: Motion.minTouchTarget)
            .background(Tokens.raised, in: RR(radius))
            .overlay(RR(radius).strokeBorder(Tokens.border, lineWidth: 1))
            .contentShape(RR(radius))
            .animation(Motion.emphasis, value: phase)
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.button, radius: radius))
        .disabled(!enabled || phase != .idle)
    }
}

struct MotionIconButton<Content: View>: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            content
                .frame(minWidth: Motion.minTouchTarget, minHeight: Motion.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.icon, radius: 24))
        .accessibilityLabel(Text(label))
    }
}

struct MotionSegmentedControl: View {
    let options: [String]
    @Binding var selected: Int
    var emphasis = false
    var height: CGFloat = 44
    var corner: CGFloat = 12
    var fontSize: CGFloat = 14
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / CGFloat(max(options.count, 1))
            ZStack(alignment: .leading) {
                RR(corner - 3)
                    .fill(emphasis ? Tokens.accent.opacity(scheme == .dark ? 0.16 : 0.20) : Tokens.raised)
                    .overlay { if emphasis { RR(corner - 3).strokeBorder(Tokens.accent.opacity(0.30), lineWidth: 1) } }
                    .frame(width: w)
                    .offset(x: (direction == .rightToLeft ? -1 : 1) * w * CGFloat(selected))
                    .animation(Motion.press, value: selected)
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                        let on = index == selected
                        Button {
                            guard !on else { return }
                            HapticEngine.play(.selection)
                            selected = index
                        } label: {
                            Text(verbatim: label)
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundStyle(on ? (emphasis ? Tokens.accent : Tokens.text) : Tokens.textMuted)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .frame(width: w, height: g.size.height)
                                .contentShape(Rectangle())
                                .animation(Motion.standard, value: on)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: height)
        .background(Tokens.well, in: RR(corner))
        .clipShape(RR(corner))
    }
}

struct MotionText: View {
    let text: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.accentText)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(DarsPress(scale: 0.94, radius: 6))
    }
}

struct SectionHead: View {
    let title: String
    var count: Int? = nil
    var icon: String? = nil
    var tint: Color? = nil
    var action: LocalizedStringKey? = nil
    var onAction: (() -> Void)? = nil
    var first = false
    var note: String? = nil

    var body: some View {
        let colour = tint ?? Tokens.textMuted
        HStack {
            HStack(spacing: 6) {
                if let icon { MaterialIcon(icon, size: 14).foregroundStyle(colour) }
                Text(verbatim: count.map { "\(title.uppercased()) · \($0)" } ?? title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .darsTracking(0.8)
                    .foregroundStyle(colour)
            }
            Spacer(minLength: 8)
            if let note {
                Text(verbatim: note).font(.system(size: 13, weight: .medium)).foregroundStyle(Tokens.textMuted)
            }
            if let action, let onAction { MotionText(text: action, action: onAction) }
        }
        .padding(.top, first ? 8 : 24)
        .padding(.bottom, 10)
    }
}

struct ScreenTitleBar<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    var progress: CGFloat = 0
    @ViewBuilder var actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let shrink = reduce ? 0 : min(max(progress, 0), 1)
        let scale = 1 - (1 - 17.0 / 28.0) * shrink
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.system(size: 28, weight: .heavy))
                        .darsTracking(-0.8)
                        .foregroundStyle(Tokens.text)
                        .lineLimit(1)
                        .scaleEffect(scale, anchor: direction == .rightToLeft ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.textMuted)
                            .lineLimit(1)
                            .opacity(1 - min(shrink * 1.5, 1))
                            .scaleEffect(x: 1, y: max(1 - shrink, 0.001), anchor: .top)
                            .frame(height: 16 * (1 - shrink), alignment: .top)
                    }
                }
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8 - 4 * shrink)
            Rectangle().fill(Tokens.border.opacity(shrink)).frame(height: 0.5)
        }
    }
}

extension ScreenTitleBar where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, progress: CGFloat = 0) {
        self.init(title: title, subtitle: subtitle, progress: progress) { EmptyView() }
    }
}

struct ScrollOffsetReader: View {
    let space: String
    @Binding var offset: CGFloat
    var body: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(space)).minY
            } action: { value in
                offset = -value
            }
    }
}

struct DarsSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var corner: CGFloat = 8
    var delay: Double = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.layoutDirection) private var direction
    @State private var start = Date()

    var body: some View {
        let dark = scheme == .dark
        let base = Tokens.text.opacity(dark ? 0.10 : 0.08)
        let sheen = Tokens.text.opacity(dark ? 0.14 : 0.11)
        TimelineView(.animation(paused: reduce)) { context in
            GeometryReader { g in
                let t = max(context.date.timeIntervalSince(start) - delay, 0)
                let raw = (t.truncatingRemainder(dividingBy: 1.15)) / 1.15
                let p = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.45, y: 0), endControlPoint: UnitPoint(x: 0.55, y: 1)).value(at: raw)
                let band = g.size.width * 0.45
                let head = -band + CGFloat(p) * (g.size.width + band * 2)
                ZStack(alignment: .leading) {
                    base
                    if !reduce {
                        LinearGradient(colors: [.clear, sheen, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: direction == .rightToLeft ? g.size.width - head - band : head)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .clipShape(RR(corner))
        .accessibilityHidden(true)
    }
}

struct DarsSkeletonList: View {
    let count: Int
    let height: CGFloat
    let corner: CGFloat
    var spacing: CGFloat = 12
    var padding: CGFloat = 16
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                DarsSkeleton(height: height, corner: corner, delay: Double(i) * 0.09)
            }
        }
        .padding(padding)
    }
}

struct DarsEmpty<Action: View>: View {
    let title: String
    var body_: String? = nil
    var icon: String? = nil
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 10) {
            if let icon { MaterialIcon(icon, size: 40).foregroundStyle(Tokens.textSub) }
            Text(verbatim: title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Tokens.text).multilineTextAlignment(.center)
            if let body_ { Text(verbatim: body_).font(.system(size: 13)).foregroundStyle(Tokens.textSub).multilineTextAlignment(.center) }
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

extension DarsEmpty where Action == EmptyView {
    init(title: String, body: String? = nil, icon: String? = nil) {
        self.init(title: title, body_: body, icon: icon) { EmptyView() }
    }
}

struct DarsError: View {
    let message: String
    var retry: LocalizedStringKey = "Try again"
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            MaterialIcon("Filled.ErrorOutline", size: 36).foregroundStyle(Tokens.danger)
            Text(verbatim: message).font(.system(size: 15)).foregroundStyle(Tokens.text).multilineTextAlignment(.center)
            MotionButton(title: retry, action: onRetry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

enum MessageTone { case error, success, info }

struct MessageLine: View {
    let message: String?
    var tone: MessageTone = .error
    var body: some View {
        let colour: Color = tone == .error ? Tokens.danger : (tone == .success ? Tokens.success : Tokens.textSub)
        VStack {
            if let message {
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(colour).frame(width: 6, height: 6).padding(.top, 5)
                    Text(verbatim: message).font(.system(size: 13)).foregroundStyle(colour)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colour.opacity(0.12), in: RR(12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.emphasis, value: message)
    }
}

struct PersonAvatar: View {
    let initials: String
    let url: String?
    let colour: Color
    var size: CGFloat = 40

    var body: some View {
        let letters = Circle().fill(colour).overlay {
            Text(verbatim: initials)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        Group {
            if let url, !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { letters }
                }
            } else {
                letters
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct ProgressRing<Content: View>: View {
    let progress: Double
    var arc: Color? = nil
    var stroke: CGFloat = 8
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0

    var body: some View {
        let colour = arc ?? Tokens.accent
        ZStack {
            Circle().stroke(colour.opacity(0.14), lineWidth: stroke).padding(stroke / 2)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [colour, colour.opacity(0.55), colour], center: .center), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(stroke / 2)
            content
        }
        .onAppear { animate(to: progress) }
        .onChange(of: progress) { _, v in animate(to: v) }
    }

    private func animate(to value: Double) {
        let target = min(max(value, 0), 1)
        if reduce { shown = target; return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)) { shown = target }
    }
}

struct CountingNumber: View, Animatable {
    var value: Double
    var suffix: String = ""
    var font: Font = .system(size: 24, weight: .bold)
    var tracking: CGFloat = -0.5

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: "\(Int(value.rounded()))\(suffix)")
            .font(font)
            .monospacedDigit()
            .darsTracking(tracking)
    }
}

struct AnimatedNumber: View {
    let value: Int
    var suffix: String = ""
    var font: Font = .system(size: 24, weight: .bold)
    var colour: Color = Tokens.text
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0

    var body: some View {
        CountingNumber(value: shown, suffix: suffix, font: font)
            .foregroundStyle(colour)
            .onAppear { go(value) }
            .onChange(of: value) { _, v in go(v) }
    }

    private func go(_ v: Int) {
        if reduce { shown = Double(v); return }
        withAnimation(Motion.arrive) { shown = Double(v) }
    }
}

enum SubjectIcon {
    static func of(_ subject: String?) -> String {
        switch subject?.trimmingCharacters(in: .whitespaces) {
        case "Mathematics", "Maths", "Math": return "Filled.Calculate"
        case "Physics", "Chemistry": return "Filled.Science"
        case "English": return "Filled.Spellcheck"
        case "Biology": return "Filled.Public"
        case "Kurdish", "Arabic": return "Filled.Translate"
        default: return "AutoMirrored.Filled.MenuBook"
        }
    }
}
