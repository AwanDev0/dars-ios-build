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
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
                .blur(radius: locked ? 18 : 0)
                .allowsHitTesting(!locked)
            if locked {
                lockScreen.transition(.opacity)
            }
        }
        .animation(Motion.symmetric, value: locked)
        .onAppear { if settings.lockEnabled { locked = true; Task { await unlock() } } }
        .onChange(of: phase) { _, new in
            guard settings.lockEnabled else { return }
            if new == .background { locked = true }
            if new == .active, locked, !asking { Task { await unlock() } }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: Metrics.Space.lg) {
            Spacer()
            Image(systemName: SettingsStore.biometry.symbol).font(.system(size: 54, weight: .light)).foregroundStyle(DarsColor.accent)
            Text("Dars is locked").darsType(.title2).foregroundStyle(DarsColor.labelPrimary)
            Spacer()
            DarsButton(title: "Unlock", kind: .primary, systemImage: "lock.open", fullWidth: true) { Task { await unlock() } }
                .padding(.horizontal, Metrics.Space.lg)
                .padding(.bottom, Metrics.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DarsColor.backgroundBase.opacity(0.6).ignoresSafeArea())
    }

    private func unlock() async {
        asking = true
        defer { asking = false }
        if await SettingsStore.authenticate(reason: "Unlock Dars") {
            HapticEngine.play(.success)
            locked = false
        }
    }
}
