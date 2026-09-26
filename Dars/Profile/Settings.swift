import Foundation
import LocalAuthentication
import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private static let modeKey = "dars.appearance"
    private static let lockKey = "dars.appLock"

    var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    var lockEnabled: Bool {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: Self.lockKey) }
    }

    init() {
        mode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .system
        lockEnabled = UserDefaults.standard.bool(forKey: Self.lockKey)
    }

    static var biometry: (available: Bool, name: String, symbol: String) {
        let ctx = LAContext()
        var err: NSError?
        let ok = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
        switch ctx.biometryType {
        case .faceID: return (ok, "Face ID", "faceid")
        case .touchID: return (ok, "Touch ID", "touchid")
        case .opticID: return (ok, "Optic ID", "opticid")
        default: return (ok, "Passcode", "lock")
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

struct LockGate<Content: View>: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var phase
    @State private var locked = false
    @State private var asking = false
    @State private var failed = false
    @State private var shielded = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
                .allowsHitTesting(!locked)
            if locked {
                LockScreen(failed: failed) { Task { await unlock() } }
                    .transition(.opacity)
            }
            if shielded && !locked {
                PrivacyShield()
                    .transition(.opacity.animation(Motion.standard))
            }
        }
        .animation(Motion.standard, value: locked)
        .onAppear {
            if settings.lockEnabled {
                locked = true
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    await unlock()
                }
            }
        }
        .onChange(of: phase) { _, new in
            guard settings.lockEnabled else {
                shielded = false
                return
            }
            if new == .background { locked = true }
            shielded = new != .active
            if new == .active, locked, !asking {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    await unlock()
                }
            }
        }
    }

    private func unlock() async {
        guard !asking else { return }
        asking = true
        failed = false
        defer { asking = false }
        if await SettingsStore.authenticate(reason: L("lock_subtitle")) {
            HapticEngine.play(.success)
            locked = false
        } else {
            failed = true
        }
    }
}

struct LockScreen: View {
    let failed: Bool
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HeroMark()
                .darsEnterHero()
            Text(verbatim: L("lock_locked"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.text)
                .darsEnter()
            Text(verbatim: L("lock_subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textMuted)
                .multilineTextAlignment(.center)
                .darsEnter()
            if failed {
                Text(verbatim: L("lock_failed"))
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.danger)
                    .multilineTextAlignment(.center)
            }
            MotionButton(title: LocalizedStringKey(L("lock_unlock")), action: onUnlock)
                .darsEnter()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg.ignoresSafeArea())
    }
}

struct PrivacyShield: View {
    var body: some View {
        VStack(spacing: 18) {
            HeroMark()
            Text(verbatim: L("lock_locked"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}
