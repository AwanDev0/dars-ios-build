import SwiftUI

struct DarsBookShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 346
        let sy = rect.height / 440
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.addRoundedRect(in: CGRect(origin: p(0, 0), size: CGSize(width: 346 * sx, height: 440 * sy)), cornerSize: CGSize(width: 40 * sx, height: 40 * sy), style: .circular)
        path.addRect(CGRect(origin: p(57, 0), size: CGSize(width: 21 * sx, height: 440 * sy)))
        path.move(to: p(240, 0))
        path.addLine(to: p(293, 0))
        path.addLine(to: p(293, 186.5))
        path.addLine(to: p(267, 145))
        path.addLine(to: p(240, 186.5))
        path.closeSubpath()
        return path
    }
}

struct DarsBook: View {
    var colour: Color = Color(hex: 0x151109)
    var body: some View {
        DarsBookShape().fill(colour, style: FillStyle(eoFill: true))
    }
}

struct AuthCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.card.opacity(0.94), in: RR(28))
            .overlay(RR(28).strokeBorder(Tokens.border, lineWidth: 1))
    }
}

struct PanelHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 23, weight: .semibold))
                .darsTracking(-0.6)
                .foregroundStyle(Tokens.text)
            Text(verbatim: subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Tokens.textSub)
                .padding(.top, 3)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AuthField: View {
    @Binding var text: String
    let icon: String
    var label: String? = nil
    var placeholder: String = ""
    var secure = false
    var revealed = false
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .never
    var submit: SubmitLabel = .next
    var onSubmit: () -> Void = {}
    var onReveal: (() -> Void)? = nil

    private enum Box: Hashable { case plain, hidden }
    @FocusState private var focus: Box?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.layoutDirection) private var direction
    @State private var dip: CGFloat = 1
    @State private var shown = false

    private var focused: Bool { focus != nil }

    var body: some View {
        let raised = label != nil && (focused || !text.isEmpty)
        HStack(spacing: 10) {
            ZStack {
                RR(11).fill(focused ? Tokens.gold.opacity(0.16) : Tokens.card)
                MaterialIcon(icon, size: 18).foregroundStyle(focused ? Tokens.gold : Tokens.textSub)
            }
            .frame(width: 36, height: 36)

            ZStack(alignment: label != nil ? .bottomLeading : .leading) {
                if let label {
                    Text(verbatim: label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(raised ? (focused ? Tokens.gold : Tokens.textSub) : Tokens.textMuted)
                        .lineLimit(1)
                        .scaleEffect(raised ? 1 : 1.36, anchor: direction == .rightToLeft ? .trailing : .leading)
                        .offset(y: raised ? 0 : 10)
                        .padding(.top, 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
                if text.isEmpty && (label == nil || focused) && !placeholder.isEmpty {
                    Text(verbatim: placeholder)
                        .font(.system(size: 16))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(1)
                        .padding(.bottom, label != nil ? 3 : 0)
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(Motion.instant))
                }
                fields
                    .padding(.bottom, label != nil ? 3 : 0)
                    .opacity((label == nil || raised ? 1 : 0.02) * (0.25 + 0.75 * dip))
                    .scaleEffect(x: 1, y: 0.82 + 0.18 * dip)
            }
            .frame(height: label != nil ? 44 : 36)

            if let onReveal {
                PasswordRevealToggle(revealed: revealed, action: onReveal)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(Tokens.well, in: RR(16))
        .overlay {
            RR(16).inset(by: 3).stroke(Tokens.gold.opacity(focused ? 0.11 : 0), lineWidth: 6)
        }
        .overlay(RR(16).strokeBorder(focused ? Tokens.gold.opacity(0.78) : Tokens.border, lineWidth: 1))
        .scaleEffect(focused && !reduce ? 1.008 : 1)
        .animation(Motion.standard, value: focused)
        .animation(Motion.standard, value: raised)
        .contentShape(Rectangle())
        .onTapGesture { focus = secure && !shown ? .hidden : .plain }
        .padding(.vertical, 5)
        .onAppear { shown = revealed }
        .onChange(of: revealed) { _, now in
            guard now != shown else { return }
            let wasFocused = focused
            if reduce || text.isEmpty {
                shown = now
                if wasFocused { focus = now ? .plain : .hidden }
                return
            }
            withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: 0.09), completionCriteria: .logicallyComplete) {
                dip = 0
            } completion: {
                shown = now
                if wasFocused { focus = now ? .plain : .hidden }
                withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.18)) { dip = 1 }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        let showPlain = !secure || shown
        ZStack {
            TextField("", text: $text)
                .focused($focus, equals: .plain)
                .opacity(showPlain ? 1 : 0)
                .allowsHitTesting(showPlain)
            if secure {
                SecureField("", text: $text)
                    .focused($focus, equals: .hidden)
                    .opacity(showPlain ? 0 : 1)
                    .allowsHitTesting(!showPlain)
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Tokens.text)
        .tint(Tokens.gold)
        .keyboardType(keyboard)
        .textContentType(content)
        .textInputAutocapitalization(capitalization)
        .autocorrectionDisabled()
        .submitLabel(submit)
        .onSubmit(onSubmit)
    }
}

struct PasswordRevealToggle: View {
    let revealed: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var open: CGFloat = 0
    @State private var look: CGFloat = 0
    @State private var bounce: CGFloat = 1

    var body: some View {
        MotionIconButton(label: revealed ? "Hide password" : "Show password", action: action) {
            RevealEye(open: open, look: look, lid: Tokens.textSub, pupil: Tokens.onAccent)
                .frame(width: 24, height: 24)
                .scaleEffect(bounce)
        }
        .onAppear { open = revealed ? 1 : 0 }
        .onChange(of: revealed) { _, now in
            if reduce {
                open = now ? 1 : 0
                look = 0
                return
            }
            if now {
                withAnimation(Motion.moment) { open = 1 }
                look = -0.55
                withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.14), completionCriteria: .logicallyComplete) { look = 0.35 } completion: {
                    withAnimation(Motion.press) { look = 0 }
                }
            } else {
                withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: 0.2)) { open = 0 }
                look = 0
            }
            withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: 0.1), completionCriteria: .logicallyComplete) { bounce = 0.88 } completion: {
                withAnimation(Motion.press) { bounce = 1 }
            }
        }
    }
}

private struct RevealEye: View, Animatable {
    var open: CGFloat
    var look: CGFloat
    let lid: Color
    let pupil: Color

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(open, look) }
        set { open = newValue.first; look = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let o = min(max(open, 0), 1.08)
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let half = w * 0.40
            let lift = h * 0.30 * o
            let bow = h * 0.16
            let strokeWidth = w * 0.085
            let left = CGPoint(x: cx - half, y: cy)
            let right = CGPoint(x: cx + half, y: cy)
            var almond = Path()
            almond.move(to: left)
            almond.addQuadCurve(to: right, control: CGPoint(x: cx, y: cy + bow * 2 - (bow * 2 + lift * 1.9) * o))
            almond.addQuadCurve(to: left, control: CGPoint(x: cx, y: cy + bow * 2 + lift * 1.2))
            almond.closeSubpath()

            if o > 0.02 {
                let r = w * 0.19 * min(o, 1)
                let ic = CGPoint(x: cx + look * r, y: cy)
                ctx.drawLayer { layer in
                    layer.clip(to: almond)
                    layer.fill(Path(ellipseIn: CGRect(x: ic.x - r, y: ic.y - r, width: r * 2, height: r * 2)), with: .color(Tokens.gold))
                    let pr = r * 0.46
                    layer.fill(Path(ellipseIn: CGRect(x: ic.x - pr, y: ic.y - pr, width: pr * 2, height: pr * 2)), with: .color(pupil))
                    let gr = r * 0.16
                    let gc = CGPoint(x: ic.x - r * 0.32, y: ic.y - r * 0.34)
                    layer.fill(Path(ellipseIn: CGRect(x: gc.x - gr, y: gc.y - gr, width: gr * 2, height: gr * 2)), with: .color(.white.opacity(0.9)))
                }
            }
            ctx.stroke(almond, with: .color(lid), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

            let lash = min(max(1 - o, 0), 1)
            if lash > 0 {
                let len = h * 0.13 * lash
                for (i, f) in [CGFloat(-0.55), 0, 0.55].enumerated() {
                    let x = cx + f * half
                    let s = (f + 1) / 2
                    let y = cy + 4 * bow * s * (1 - s)
                    let l = i == 1 ? len : len * 0.85
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: y + strokeWidth * 0.5))
                    line.addLine(to: CGPoint(x: x + f * l * 0.7, y: y + l + strokeWidth * 0.5))
                    ctx.stroke(line, with: .color(lid.opacity(lash)), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                }
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let enabled: Bool
    let working: Bool
    let action: () -> Void

    var body: some View {
        let alpha: Double = enabled || working ? 1 : 0.55
        Button(action: action) {
            ZStack {
                if working {
                    ProgressView().tint(Tokens.onAction).transition(.opacity)
                } else {
                    ZStack(alignment: .trailing) {
                        Text(verbatim: title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tokens.onAction.opacity(alpha))
                            .frame(maxWidth: .infinity)
                        MaterialIcon("AutoMirrored.Filled.ArrowForward", size: 20)
                            .foregroundStyle(Tokens.gold.opacity(alpha))
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 22)
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(Tokens.action, in: RR(16))
            .overlay(RR(16).strokeBorder(Tokens.border, lineWidth: 1))
            .contentShape(RR(16))
            .animation(Motion.emphasis, value: working)
            .animation(Motion.standard, value: enabled)
        }
        .buttonStyle(ScalePress(scale: Motion.Scale.primary))
        .disabled(!enabled || working)
    }
}

struct ScalePress: ButtonStyle {
    var scale: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        ScaleLabel(configuration: configuration, scale: scale)
    }
    private struct ScaleLabel: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduce
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduce ? scale : 1)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

struct Reassure: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MaterialIcon(icon, size: 15).foregroundStyle(Tokens.accentText).padding(.top, 1)
            Text(verbatim: text).font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Tokens.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }
}

struct StepsLine: View {
    let current: Int
    let labels: [String]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let done = index < current
                let now = index == current
                HStack(spacing: 5) {
                    if done {
                        MaterialIcon("Filled.Check", size: 12)
                    } else {
                        Text(verbatim: "\(index + 1)").font(.system(size: 11, weight: .bold))
                    }
                    Text(verbatim: label).font(.system(size: 11.5, weight: now ? .semibold : .medium)).lineLimit(1)
                }
                .foregroundStyle(now ? Tokens.onAccent : (done ? Tokens.accentText : Tokens.textMuted))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(now ? Tokens.gold : (done ? Tokens.accentSoft : Tokens.well), in: RR(13))
                .animation(Motion.standard, value: current)
                if index < labels.count - 1 {
                    Rectangle()
                        .fill(index < current ? Tokens.gold.opacity(0.6) : Tokens.border)
                        .frame(height: 1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.bottom, 16)
    }
}

struct BackDot: View {
    let action: () -> Void
    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            MaterialIcon("AutoMirrored.Filled.ArrowBackIos", size: 17)
                .foregroundStyle(Tokens.text)
                .frame(width: 38, height: 38)
                .background(Tokens.cardAlt, in: Circle())
                .overlay(Circle().strokeBorder(Tokens.border, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(ScalePress(scale: Motion.Scale.icon))
        .accessibilityLabel(Text(verbatim: L("cd_back")))
    }
}

struct AuthShell<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Tokens.bg.ignoresSafeArea()
            LoginBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        BackDot(action: onBack)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: title)
                                .font(.system(size: 28, weight: .heavy))
                                .darsTracking(-0.8)
                                .foregroundStyle(Tokens.text)
                                .lineLimit(1)
                            if let subtitle {
                                Text(verbatim: subtitle).font(.system(size: 13)).foregroundStyle(Tokens.textMuted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .darsEnter()
                    VStack(alignment: .leading, spacing: 0) { content }
                        .darsEnter(delay: 0.11)
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct AuthLabel: View {
    let text: String
    var body: some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .darsTracking(0.6)
            .foregroundStyle(Tokens.textMuted)
            .padding(.bottom, 4)
    }
}

struct ChoiceCard: View {
    let title: String
    let icon: String
    let selected: Bool
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MaterialIcon(icon, size: 18)
                        .foregroundStyle(selected ? Tokens.onAccent : Tokens.textSub)
                        .frame(width: 34, height: 34)
                        .background(selected ? Tokens.accent : Tokens.well, in: Circle())
                    Spacer()
                    if selected {
                        MaterialIcon("Filled.CheckCircle", size: 20)
                            .foregroundStyle(Tokens.accentText)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                if let subtitle {
                    Text(verbatim: subtitle).font(.system(size: 12)).foregroundStyle(Tokens.textSub).lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Tokens.accent.opacity(0.10) : Tokens.card, in: RR(16))
            .overlay(RR(16).strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: 1))
            .contentShape(RR(16))
            .animation(Motion.standard, value: selected)
        }
        .buttonStyle(ScalePress(scale: Motion.Scale.row))
    }
}

struct NameRow: View {
    let name: String
    let initials: String
    let colour: Color
    var avatarURL: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            HStack(spacing: 12) {
                PersonAvatar(initials: initials, url: avatarURL, colour: colour, size: 38)
                Text(verbatim: name).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Tokens.text).lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    MaterialIcon("Filled.CheckCircle", size: 20)
                        .foregroundStyle(Tokens.accentText)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(12)
            .background(selected ? Tokens.accent.opacity(0.10) : Tokens.card, in: RR(16))
            .overlay(RR(16).strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: 1))
            .contentShape(RR(16))
            .animation(Motion.standard, value: selected)
        }
        .buttonStyle(ScalePress(scale: Motion.Scale.row))
    }
}

struct CreditLine: View {
    var compact = false
    var onOpen: (() -> Void)? = nil

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let lead = compact ? "" : "Dars \(version)  ·  "
        (Text(verbatim: "\(lead)\u{00a9} 2026 ") + Text(verbatim: L("about_author")).foregroundColor(Tokens.accent).fontWeight(.semibold))
            .font(.system(size: 11))
            .darsTracking(0.2)
            .foregroundStyle(Tokens.textFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
    }
}

struct HeroMark: View {
    var shine: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var arrival: CGFloat = 0
    @State private var wobble: Double = 0
    @State private var spin: Double = 0
    @State private var holds = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFDE7A), Color(hex: 0xFAB900), Color(hex: 0xE08A00)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                ZStack {
                    RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: UnitPoint(x: 0.22, y: 0.18), startRadius: 0, endRadius: g.size.width * 0.75)
                    LinearGradient(colors: [.clear, Color(hex: 0x8A5200).opacity(0.16)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                }
            }
            DarsBook(colour: Color.black.opacity(0.18))
                .frame(width: 33, height: 42)
                .offset(x: 1, y: 2.5)
                .blur(radius: 2)
            DarsBook()
                .frame(width: 33, height: 42)
            ShineSweep(progress: arrival)
        }
        .frame(width: 96, height: 96)
        .clipShape(RR(26))
        .rotationEffect(.degrees(wobble + spin))
        .accessibilityLabel(Text(verbatim: L("app_name")))
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !reduce else { return }
            holds += 1
            HapticEngine.play(.success)
            if holds % 5 == 0 {
                spin = 0
                withAnimation(.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.7), completionCriteria: .logicallyComplete) { spin = 360 } completion: { spin = 0 }
            } else {
                Task { @MainActor in
                    let frames: [(Double, Double)] = [(-9, 0.08), (8, 0.10), (-5, 0.11), (3, 0.11), (0, 0.12)]
                    for (angle, duration) in frames {
                        withAnimation(.linear(duration: duration)) { wobble = angle }
                        try? await Task.sleep(for: .seconds(duration))
                    }
                }
            }
        }
        .onChange(of: shine) { _, now in
            guard now, !reduce else { return }
            arrival = 0
            withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 0.7)) { arrival = 1 }
        }
    }
}

private struct ShineSweep: View, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        GeometryReader { g in
            if progress > 0 && progress < 1 {
                let x = g.size.width * (-0.6 + 2.2 * progress)
                LinearGradient(colors: [.clear, Color.white.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: g.size.width * 0.55, height: g.size.height)
                    .offset(x: x)
            }
        }
        .allowsHitTesting(false)
    }
}

struct LoginBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduce)) { context in
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, t: reduce ? 0 : context.date.timeIntervalSince(start) * 1000)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func warm(_ s: Double) -> Color {
        scheme == .dark ? Color(hex: 0x2A2118).opacity(min(max(0.50 * s, 0), 1)) : Color(hex: 0xEFE9E0).opacity(min(max(0.55 * s, 0), 1))
    }

    private func rim(_ s: Double) -> Color {
        scheme == .dark ? Color(hex: 0x6B5B45).opacity(min(max(0.26 * s, 0), 1)) : Color.white.opacity(min(max(0.85 * s, 0), 1))
    }

    private func arc(_ box: CGRect, start: Double, sweep: Double) -> Path {
        var path = Path()
        let steps = max(Int(abs(sweep) / 2), 2)
        for i in 0...steps {
            let deg = start + sweep * Double(i) / Double(steps)
            let rad = deg * .pi / 180
            let point = CGPoint(x: box.midX + box.width / 2 * cos(rad), y: box.midY + box.height / 2 * sin(rad))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func draw(ctx: GraphicsContext, size: CGSize, t: Double) {
        let w = size.width
        let h: CGFloat = 330
        let breathe = sin(2 * .pi * t / 13_000)
        let float = sin(2 * .pi * t / 7_000)
        let lean = sin(2 * .pi * t / 17_000)
        let travel = (t / 9_000).truncatingRemainder(dividingBy: 1)
        let dx = 6 * breathe
        let dy = 4 * breathe

        let band = CGRect(x: w * 0.12 + dx, y: -h * 0.55 + dy, width: w * 1.30, height: h * 1.55)
        let bandStart = 120 + 3 * breathe
        let bandSweep: Double = 130
        ctx.stroke(
            arc(band, start: bandStart, sweep: bandSweep),
            with: .linearGradient(Gradient(colors: [rim(0.95), warm(0.85), warm(0.35)]), startPoint: CGPoint(x: w * 0.2, y: 0), endPoint: CGPoint(x: w, y: h * 0.8)),
            style: StrokeStyle(lineWidth: w * 0.19, lineCap: .round)
        )
        ctx.stroke(
            arc(band, start: bandStart + 8, sweep: 110),
            with: .linearGradient(Gradient(colors: [warm(0.20), .clear]), startPoint: CGPoint(x: w * 0.3, y: h * 0.1), endPoint: CGPoint(x: w, y: h * 0.6)),
            style: StrokeStyle(lineWidth: w * 0.06, lineCap: .round)
        )
        if !reduce {
            let run: Double = 22
            let glow = sin(Double.pi * travel)
            let at = bandStart - run / 2 + (bandSweep + run) * travel
            func onBand(_ deg: Double) -> CGPoint {
                let rad = deg * .pi / 180
                return CGPoint(x: band.midX + band.width / 2 * cos(rad), y: band.midY + band.height / 2 * sin(rad))
            }
            ctx.stroke(
                arc(band, start: at, sweep: run),
                with: .linearGradient(Gradient(colors: [.clear, rim(1.4 * glow), .clear]), startPoint: onBand(at), endPoint: onBand(at + run)),
                style: StrokeStyle(lineWidth: w * 0.15, lineCap: .round)
            )
        }
        let low = CGRect(x: w * 0.30 - dx * 0.5, y: h * 0.08, width: w * 1.10, height: h * 0.86)
        ctx.stroke(
            arc(low, start: 155 + 4 * lean, sweep: 95),
            with: .linearGradient(Gradient(colors: [warm(0.55), rim(0.70)]), startPoint: CGPoint(x: w * 0.3, y: h * 0.5), endPoint: CGPoint(x: w, y: h * 0.2)),
            style: StrokeStyle(lineWidth: w * 0.13, lineCap: .round)
        )
        let sphere = CGPoint(x: w * 0.86, y: h * 0.24 + 5 * float)
        let r = w * 0.20
        ctx.fill(
            Path(ellipseIn: CGRect(x: sphere.x - r, y: sphere.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(Gradient(colors: [rim(1), warm(0.72), warm(0.30)]), center: CGPoint(x: sphere.x - r * 0.35, y: sphere.y - r * 0.40), startRadius: 0, endRadius: r * 1.6)
        )
        let shade = scheme == .dark ? Color.black.opacity(0.35) : Color(hex: 0x6E6459).opacity(0.07)
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .radialGradient(Gradient(colors: [shade, .clear]), center: CGPoint(x: w * 0.66 + dx * 0.5, y: h * 0.62 + dy), startRadius: 0, endRadius: w * 0.72)
        )
        let minDim = min(size.width, size.height)
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(Gradient(colors: [warm(0.40), .clear]), center: CGPoint(x: size.width * 0.08 + dx * 2, y: size.height * 0.72 - dy * 2), startRadius: 0, endRadius: minDim * 0.95)
        )
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(Gradient(colors: [rim(0.30), .clear]), center: CGPoint(x: size.width * 1.02 - dx * 1.5, y: size.height * 0.88 + dy), startRadius: 0, endRadius: minDim * 0.85)
        )
    }
}

enum Whimsy { case snow, books }

struct LoginWhimsy: View {
    let request: (Whimsy, Date)?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var start = Date()

    var body: some View {
        if !reduce {
            TimelineView(.animation) { context in
                Canvas { ctx, size in draw(ctx: ctx, size: size, now: context.date) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private static func hash(_ i: Int) -> CGFloat {
        var x = UInt64(truncatingIfNeeded: Int64(i)) &* 2654435761
        x ^= x >> 13
        x = x &* 1274126177
        x ^= x >> 16
        return CGFloat(x & 0xFFFF) / 65535
    }

    private func draw(ctx: GraphicsContext, size: CGSize, now: Date) {
        let w = size.width
        let h = size.height
        let t = now.timeIntervalSince(start) * 1000
        let cycle = t.truncatingRemainder(dividingBy: 64_000)
        let ambient = cycle < 8_000
        let ambientAt = cycle / 8_000
        let asked = request.map { ($0.0, now.timeIntervalSince($0.1) * 1000) }
        let snowing = asked?.0 == .snow && (asked.map { $0.1 >= 0 && $0.1 <= 12_000 } ?? false)
        let raining = asked?.0 == .books && (asked.map { $0.1 >= 0 && $0.1 <= 9_000 } ?? false)
        let ink: Color = scheme == .dark ? .white : .black

        if ambient || raining {
            let count = raining ? 18 : 4
            let progress = raining ? (asked!.1 / 9_000) : ambientAt
            for i in 0..<count {
                let r1 = Self.hash(i * 7 + 1)
                let r2 = Self.hash(i * 7 + 2)
                let r3 = Self.hash(i * 7 + 3)
                let p = (CGFloat(progress) - r1 * 0.5) / 0.55
                guard p >= 0, p <= 1 else { continue }
                let side = 26 + 22 * r2
                let x = w * (0.05 + 0.9 * r3) + sin(2 * .pi * (p * 1.5 + r2)) * 14
                let y = -side + (h + side * 2) * p
                let alpha = min(max((raining ? 0.10 : 0.06) * max(min(sin(.pi * p), 1), 0) * 2, 0), 0.12)
                let degrees = -25 + 50 * r1 + 40 * p * (r2 > 0.5 ? 1 : -1)
                var layer = ctx
                layer.translateBy(x: x + side / 2, y: y + side / 2)
                layer.rotate(by: .degrees(Double(degrees)))
                let bookW = side * 346 / 440
                let path = DarsBookShape().path(in: CGRect(x: -bookW / 2, y: -side / 2, width: bookW, height: side))
                layer.fill(path, with: .color(ink.opacity(alpha)), style: FillStyle(eoFill: true))
            }
        }

        if snowing {
            let elapsed = CGFloat(asked!.1 / 1000)
            let envelope = min(elapsed, 1) * (1 - min(max((elapsed - 10) / 2, 0), 1))
            for i in 0..<90 {
                let r1 = Self.hash(i * 11 + 1)
                let r2 = Self.hash(i * 11 + 2)
                let r3 = Self.hash(i * 11 + 3)
                let speed = 0.05 + 0.06 * r2
                let p = (elapsed * speed + r1).truncatingRemainder(dividingBy: 1)
                let radius = 1.2 + 2.2 * r3
                let x = w * ((r1 + 0.08 * sin(2 * .pi * (elapsed * 0.3 + r2))).truncatingRemainder(dividingBy: 1))
                let y = h * p
                ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity((0.35 + 0.45 * r2) * envelope)))
            }
        }
    }

    static func request(for typed: String) -> Whimsy? {
        let lower = typed.trimmingCharacters(in: .whitespaces).lowercased()
        if lower.hasSuffix("snow") || lower.hasSuffix("بەفر") { return .snow }
        if lower.hasSuffix("books") || lower.hasSuffix("کتێب") { return .books }
        return nil
    }
}

struct ThemeToggle: View {
    let dark: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var night: CGFloat = 0

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action()
        } label: {
            SunMoon(night: night, ink: Tokens.text)
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(-30 * Double(night)))
                .frame(width: 36, height: 36)
                .background(Tokens.card.opacity(0.72), in: Circle())
                .overlay(Circle().strokeBorder(Tokens.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.icon, radius: 18))
        .accessibilityLabel(Text(verbatim: L(dark ? "profile_light_mode" : "profile_dark_mode")))
        .onAppear { night = dark ? 1 : 0 }
        .onChange(of: dark) { _, now in
            if reduce { night = now ? 1 : 0 } else { withAnimation(Motion.moment) { night = now ? 1 : 0 } }
        }
    }
}

private struct SunMoon: View, Animatable {
    var night: CGFloat
    let ink: Color
    var animatableData: CGFloat {
        get { night }
        set { night = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let n = min(max(night, 0), 1.15)
            let m = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let colour = mix(Tokens.gold, ink, min(max(n, 0), 1))
            let r = m * (0.22 + 0.09 * n)
            let rayLen = m * 0.13 * min(max(1 - n, 0), 1)
            ctx.drawLayer { layer in
                if rayLen > 0.5 {
                    let inner = m * 0.34
                    for i in 0..<8 {
                        let a = (Double(i) * 45 + 45 * Double(n)) * .pi / 180
                        var line = Path()
                        line.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                        line.addLine(to: CGPoint(x: c.x + cos(a) * (inner + rayLen), y: c.y + sin(a) * (inner + rayLen)))
                        layer.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: m * 0.085, lineCap: .round))
                    }
                }
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(colour))
                if n > 0.02 {
                    let bite = CGPoint(x: c.x + m * (0.42 - 0.20 * n), y: c.y - m * (0.42 - 0.22 * n))
                    let br = r * 0.92
                    layer.blendMode = .clear
                    layer.fill(Path(ellipseIn: CGRect(x: bite.x - br, y: bite.y - br, width: br * 2, height: br * 2)), with: .color(.black))
                }
            }
        }
    }

    private func mix(_ a: Color, _ b: Color, _ t: CGFloat) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, opacity: aa + (ba - aa) * t)
    }
}

struct LanguageSwitch: View {
    let language: AppLanguage
    let action: (AppLanguage) -> Void

    var body: some View {
        Button {
            HapticEngine.play(.selection)
            action(language == .sorani ? .english : .sorani)
        } label: {
            ZStack {
                Text(verbatim: language == .sorani ? "English" : "کوردی")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.text)
                    .lineLimit(1)
                    .id(language)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity.combined(with: .move(edge: .top))))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Tokens.card.opacity(0.72), in: RR(18))
            .overlay(RR(18).strokeBorder(Tokens.border, lineWidth: 1))
            .clipShape(RR(18))
            .contentShape(RR(18))
            .animation(Motion.emphasis, value: language)
        }
        .buttonStyle(DarsPress(scale: Motion.Scale.button, radius: 18))
    }
}

struct DarsSheet<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(verbatim: title)
                    .font(.system(size: 22, weight: .semibold))
                    .darsTracking(-0.2)
                    .foregroundStyle(Tokens.text)
                    .padding(.bottom, 12)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationBackground(Tokens.raised)
        .presentationDragIndicator(.visible)
    }
}

extension DarsError {
    var text: String {
        switch self {
        case .badCredentials: return L("error_bad_credentials")
        case .noProfile: return L("error_no_profile")
        case .network: return L("error_network")
        case .server(let message): return message
        }
    }
}
