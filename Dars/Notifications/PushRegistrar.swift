import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications
import Supabase

@MainActor
@Observable
final class PushRegistrar: NSObject {
    static let shared = PushRegistrar()

    private(set) var authorized = false
    private(set) var asked = false
    var pendingTab: String?
    var pendingConversation: UUID?

    private var lastToken: String?
    private var signedIn = false

    private override init() { super.init() }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        asked = settings.authorizationStatus != .notDetermined
        if authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    func ask() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorized = granted
            asked = true
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            asked = true
        }
    }

    func deviceToken(_ data: Foundation.Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        lastToken = token
        if signedIn { Task { await store(token) } }
    }

    func sessionChanged(signedIn: Bool) {
        self.signedIn = signedIn
        if signedIn, let token = lastToken { Task { await store(token) } }
    }

    private func store(_ token: String) async {
        struct Args: Encodable { let p_token: String; let p_platform: String }
        do {
            try await SupabaseService.client.rpc("register_push_token", params: Args(p_token: token, p_platform: "ios-apns")).execute()
        } catch {
        }
    }

    func open(_ link: String?) {
        guard let link, let url = URL(string: link), url.scheme == "dars" else { return }
        switch url.host {
        case "messages":
            pendingTab = "messages"
            let last = url.pathComponents.last.flatMap { UUID(uuidString: $0) }
            pendingConversation = last
        case "work":       pendingTab = "work"
        case "grades":     pendingTab = "marks"
        case "attendance": pendingTab = "home"
        default:           pendingTab = "home"
        }
    }
}

extension PushRegistrar: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let link = info["link"] as? String
        await MainActor.run { PushRegistrar.shared.open(link) }
    }
}

final class DarsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in PushRegistrar.shared.start() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data) {
        Task { @MainActor in PushRegistrar.shared.deviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
}

struct NotificationPrimer: View {
    @Environment(PushRegistrar.self) private var push
    @State private var showing = false

    var body: some View {
        Group {
            if showing {
                VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge.fill").font(.system(size: 18)).foregroundStyle(DarsColor.accentLabel)
                        Text("Let the school reach you").darsType(.headline).foregroundStyle(DarsColor.labelPrimary)
                        Spacer()
                        Button { withAnimation(Motion.arrive) { showing = false } } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(DarsColor.labelTertiary)
                        }
                    }
                    Text("A message from a teacher, new homework, a mark, or your child marked absent. You choose which in Profile.")
                        .darsType(.footnote).foregroundStyle(DarsColor.labelSecondary)
                    DarsButton(title: "Turn notifications on", kind: .primary, systemImage: "bell.fill", fullWidth: true) {
                        Task { await push.ask(); withAnimation(Motion.arrive) { showing = false } }
                    }
                }
                .padding(Metrics.Space.md)
                .background(DarsColor.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DarsColor.accent.opacity(0.3), lineWidth: 1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await push.refreshStatus()
            if !push.asked { withAnimation(Motion.arrive.delay(0.6)) { showing = true } }
        }
    }
}
