import SwiftUI
import Observation

@MainActor
@Observable
final class OpeningState {
    var playing = true
    var cue = false
    var landed = false
    var resolved = false
    var mark: CGRect?

    func begin() {
        playing = true
        cue = false
        landed = false
    }
}

private struct OpeningCueKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var openingCue: Bool {
        get { self[OpeningCueKey.self] }
        set { self[OpeningCueKey.self] = newValue }
    }
}

private enum Ease {
    static let decelerate = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.46), endControlPoint: UnitPoint(x: 0.45, y: 0.94))
    static let standard = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.45, y: 0), endControlPoint: UnitPoint(x: 0.55, y: 1))
}

struct OpeningOverlay: View {
    @Environment(OpeningState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduce

    @State private var began = Date()
    @State private var fadeAt: Date?
    @State private var finishAt: Date?
    @State private var target: CGRect?
    @State private var contract = false
    @State private var pulseStop: Date?

    private let holdSeconds = 2.5
    private let wordSeconds = 0.72
    private let contractSeconds = 0.64
    private let liftSeconds = 0.42
    private let layerBook: CGFloat = 288 * 58 / 108
    private let bookAspect: CGFloat = 346 / 440

    var body: some View {
        if state.playing {
            GeometryReader { g in
                TimelineView(.animation) { context in
                    Canvas { ctx, size in
                        draw(ctx: ctx, size: size, now: context.date, origin: g.frame(in: .global).origin)
                    }
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {}
            .task { await run() }
            .accessibilityHidden(true)
        }
    }

    private func run() async {
        began = Date()
        let start = Date()
        while Date().timeIntervalSince(start) < holdSeconds && !state.resolved {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !reduce {
            let left = wordSeconds + 0.16 - Date().timeIntervalSince(began)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            fadeAt = Date()
            try? await Task.sleep(for: .milliseconds(180))
        }
        let waitStart = Date()
        while state.mark == nil && Date().timeIntervalSince(waitStart) < 0.4 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        target = state.mark
        contract = target != nil
        pulseStop = Date()
        if reduce {
            state.cue = true
            finishAt = Date().addingTimeInterval(-1)
        } else if contract {
            finishAt = Date()
            try? await Task.sleep(for: .seconds(contractSeconds * 0.3))
            state.cue = true
            try? await Task.sleep(for: .seconds(contractSeconds * 0.7))
        } else {
            state.cue = true
            finishAt = Date()
            try? await Task.sleep(for: .seconds(liftSeconds))
        }
        state.landed = true
        state.playing = false
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func draw(ctx: GraphicsContext, size: CGSize, now: Date, origin: CGPoint) {
        let gold = Color(hex: 0xFAB900)
        let full = CGRect(origin: .zero, size: size)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let wordmark = reduce ? 1 : CGFloat(min(max(now.timeIntervalSince(began) / wordSeconds, 0), 1))
        let wordEase = CGFloat(Ease.decelerate.value(at: Double(wordmark)))
        let fade = fadeAt.map { CGFloat(min(max(now.timeIntervalSince($0) / 0.18, 0), 1)) } ?? 0
        let duration = contract ? contractSeconds : liftSeconds
        let raw = finishAt.map { CGFloat(min(max(now.timeIntervalSince($0) / duration, 0), 1)) } ?? 0
        let p = CGFloat(Ease.decelerate.value(at: Double(raw)))

        var pulse: CGFloat = 0
        if !reduce && pulseStop == nil {
            let t = now.timeIntervalSince(began) - 0.12
            if t > 0 {
                let local = t.truncatingRemainder(dividingBy: 1.6)
                if local < 0.9 { pulse = CGFloat(Ease.standard.value(at: local / 0.9)) }
            }
        }

        if contract, let to0 = target {
            let to = to0.offsetBy(dx: -origin.x, dy: -origin.y)
            let rect = CGRect(
                x: mix(full.minX, to.minX, p),
                y: mix(full.minY, to.minY, p),
                width: mix(full.width, to.width, p),
                height: mix(full.height, to.height, p)
            )
            let radius = mix(0, 26 * (to.width / 96), p)
            let shape = Path(roundedRect: rect, cornerRadius: radius, style: .circular)
            ctx.fill(shape, with: .color(gold))
            var tinted = ctx
            tinted.opacity = Double(p)
            tinted.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFDE7A), gold, Color(hex: 0xE08A00)]), startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            let bookH = mix(layerBook, 42 * (to.height / 96), p)
            let bookW = bookH * bookAspect
            let c = CGPoint(x: mix(centre.x, to.midX, p), y: mix(centre.y, to.midY, p))
            let book = DarsBookShape().path(in: CGRect(x: c.x - bookW / 2, y: c.y - bookH / 2, width: bookW, height: bookH))
            ctx.fill(book, with: .color(Color(hex: 0x151109)), style: FillStyle(eoFill: true))
            if raw == 0 {
                drawWord(ctx: ctx, centre: centre, below: bookH / 2 + 18, progress: wordmark, alpha: 1 - fade)
            }
        } else {
            let alpha = min(max(1 - p * 1.15, 0), 1)
            let diagonal = hypot(size.width, size.height)
            let iris = max(p * diagonal * 0.62, 0.5)
            var cut = Path()
            cut.addRect(full)
            cut.addEllipse(in: CGRect(x: centre.x - iris, y: centre.y - iris, width: iris * 2, height: iris * 2))
            var layer = ctx
            layer.opacity = Double(alpha)
            layer.fill(cut, with: .color(gold), style: FillStyle(eoFill: true))
            let breathe = 1 + 0.05 * sin(.pi * pulse)
            let bookH = layerBook * (1 + 0.12 * p) * breathe
            let bookW = bookH * bookAspect
            let wordRise = 22 * CGFloat(Ease.decelerate.value(at: Double(min(max(wordmark * 3, 0), 1))))
            let rise = 10 * p + wordRise
            var bookLayer = ctx
            bookLayer.opacity = Double(min(max(1 - p * 1.6, 0), 1))
            let book = DarsBookShape().path(in: CGRect(x: centre.x - bookW / 2, y: centre.y - bookH / 2 - rise, width: bookW, height: bookH))
            bookLayer.fill(book, with: .color(Color(hex: 0x151109)), style: FillStyle(eoFill: true))
            drawWord(ctx: ctx, centre: centre, below: bookH / 2 - rise + 18, progress: wordmark, alpha: 1 - fade)
        }
        _ = wordEase
    }

    private func drawWord(ctx: GraphicsContext, centre: CGPoint, below: CGFloat, progress: CGFloat, alpha: CGFloat) {
        guard progress > 0, alpha > 0 else { return }
        let letters = Array("dars")
        let resolved = letters.map { ctx.resolve(Text(verbatim: String($0)).font(.system(size: 38, weight: .bold)).tracking(-0.5).foregroundColor(Color(hex: 0x09090F))) }
        let sizes = resolved.map { $0.measure(in: CGSize(width: 200, height: 100)) }
        let total = sizes.reduce(0) { $0 + $1.width }
        var x = centre.x - total / 2
        let top = centre.y + below
        for (i, text) in resolved.enumerated() {
            let start = CGFloat(i) * 0.18
            let local = min(max((progress - start) / 0.46, 0), 1)
            let e = CGFloat(Ease.decelerate.value(at: Double(local)))
            var layer = ctx
            layer.opacity = Double(min(max(e * alpha, 0), 1))
            layer.draw(text, at: CGPoint(x: x, y: top + 10 * (1 - e)), anchor: .topLeading)
            x += sizes[i].width
        }
        let tagLocal = min(max((progress - 0.62) / 0.38, 0), 1)
        if tagLocal > 0 {
            let tag = ctx.resolve(Text(verbatim: "BETA").font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(Color(hex: 0x09090F)))
            let tagSize = tag.measure(in: CGSize(width: 200, height: 40))
            var layer = ctx
            layer.opacity = Double(min(max(CGFloat(Ease.standard.value(at: Double(tagLocal))) * 0.7 * alpha, 0), 1))
            layer.draw(tag, at: CGPoint(x: centre.x - tagSize.width / 2, y: top + (sizes.first?.height ?? 40) + 6), anchor: .topLeading)
        }
    }
}
