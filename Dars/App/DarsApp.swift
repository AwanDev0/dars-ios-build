import SwiftUI

@main
struct DarsApp: App {
    @UIApplicationDelegateAdaptor(DarsAppDelegate.self) private var delegate

    @State private var auth = AuthStore()

    @State private var language = LanguageStore()

    private let palettes = PaletteStore.shared
    @State private var settings = SettingsStore()

    private let push = PushRegistrar.shared

    var body: some Scene {
        WindowGroup {
            LockGate { RootView() }
                .environment(auth)
                .environment(language)
                .environment(palettes)
                .environment(settings)
                .environment(push)
                .preferredColorScheme(settings.mode.colorScheme)
                .darsLanguage(language.language)
                .id(language.language)
                .tint(DarsColor.accent)
        }
    }
}
