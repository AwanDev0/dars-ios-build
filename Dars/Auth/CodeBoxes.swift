import SwiftUI

enum CodeState: Equatable { case idle, checking, success, error }

struct CodeBoxes: View {
    @Binding var value: String
    var length = 6
    var state: CodeState = .idle
    var autoFocus = true
    var description = ""
    var onFilled: (String) -> Void = { _ in }

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shake: CGFloat = 0
    @State private var lastFilled: String?

    var body: some View {
        ZStack {
            TextField("", text: Binding(get: { value }, set: { raw in
                let clean = String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(length))
                if clean != value {
                    if clean.count > value.count { HapticEngine.play(.impactLight) }
                    value = clean
                }
            }))
            .focused($focused)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit { if value.count == length { onFilled(value) } }
            .foregroundStyle(.clear)
            .tint(.clear)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel(Text(verbatim: description))

            HStack(spacing: 8) {
                ForEach(0..<length, id: \.self) { i in
                    let chars = Array(value)
                    CodeBox(
                        char: i < chars.count ? chars[i] : nil,
                        index: i,
                        active: focused && i == min(value.count, length - 1) && state != .success,
                        state: state,
                        isLast: i == length - 1
                    )
                }
            }
            .offset(x: shake)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { if autoFocus { focused = true } }
        .onChange(of: value) { _, now in
            if now.count == length && now != lastFilled {
                lastFilled = now
                onFilled(now)
            }
            if now.count < length { lastFilled = nil }
        }
        .onChange(of: state) { _, now in
            if now == .error {
                HapticEngine.play(.error)
                guard !reduce else { return }
                Task { @MainActor in
                    let frames: [(CGFloat, Double)] = [(-8, 0.06), (7, 0.08), (-5, 0.08), (3, 0.08), (0, 0.08)]
                    for (x, d) in frames {
                        withAnimation(.linear(duration: d)) { shake = x }
                        try? await Task.sleep(for: .seconds(d))
                    }
                }
            }
            if now == .success { HapticEngine.play(.success) }
        }
    }
}

private struct CodeBox: View {
    let char: Character?
    let index: Int
    let active: Bool
    let state: CodeState
    let isLast: Bool

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lit = false
    @State private var land: CGFloat = 1
    @State private var caretOn = true
    @State private var tick: CGFloat = 0

    var body: some View {
        let error = state == .error
        let edge: Color = lit ? Tokens.success : (error ? Tokens.danger : (active ? Tokens.gold : Tokens.border))
        let fill: Color = lit ? Tokens.success.opacity(0.14) : (error ? Tokens.danger.opacity(0.08) : (active ? Tokens.gold.opacity(0.08) : Tokens.well))
        ZStack {
            RR(14).fill(Tokens.well)
            RR(14).fill(fill)
            if lit && isLast {
                MaterialIcon("Filled.Check", size: 24)
                    .foregroundStyle(Tokens.success)
                    .scaleEffect(tick)
            } else if let char {
                Text(verbatim: String(char))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(lit ? Tokens.success : (error ? Tokens.danger : Tokens.text))
                    .scaleEffect(land)
                    .opacity(state == .checking ? 0.45 : 1)
                    .animation(.easeInOut(duration: 0.35).delay(0.05 * Double(index)), value: state == .checking)
            } else if active {
                RR(1).fill(Tokens.gold.opacity(caretOn ? 1 : 0)).frame(width: 2, height: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .overlay(RR(14).strokeBorder(edge, lineWidth: active || lit || error ? 1.6 : 1))
        .scaleEffect(active && !reduce ? 1.03 : 1)
        .animation(Motion.spring(damping: 0.7, stiffness: 300), value: active)
        .animation(Motion.standard, value: lit)
        .animation(Motion.standard, value: error)
        .onChange(of: char) { _, now in
            guard now != nil else { land = 1; return }
            if reduce { land = 1; return }
            land = 0.6
            withAnimation(Motion.spring(damping: 0.55, stiffness: 900)) { land = 1 }
        }
        .onChange(of: state) { _, now in
            if now == .success {
                if reduce {
                    lit = true
                    tick = 1
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(55 * index))
                        lit = true
                        if isLast { withAnimation(Motion.spring(damping: 0.5, stiffness: 700)) { tick = 1 } }
                    }
                }
            } else {
                lit = false
                tick = 0
            }
        }
        .task(id: active) {
            caretOn = true
            guard active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(560))
                caretOn.toggle()
            }
        }
    }
}
