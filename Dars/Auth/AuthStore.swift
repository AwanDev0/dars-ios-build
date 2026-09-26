import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(Profile)
        case orphaned
        case suspended(String?)
    }

    private(set) var state: State = .restoring
    private(set) var isWorking = false
    private(set) var error: DarsError?

    private var watcher: Task<Void, Never>?

    var profile: Profile? {
        if case .signedIn(let p) = state { return p }
        return nil
    }
    var role: Role? { profile?.role }

    func start() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            for await change in SupabaseService.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let user = change.session?.user {
                        await self.loadProfile(for: user.id)
                    } else {
                        self.state = .signedOut
                    }
                case .signedOut:
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    func signIn(email: String, password: String) async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        let typed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = typed.filter(\.isNumber)
        let isPhone = !typed.contains("@") && digits.count >= 7
        let first = isPhone ? "p\(digits)@parent.kurdedu.app" : typed

        do {
            _ = try await SupabaseService.auth.signIn(email: first, password: password)
        } catch let authError as AuthError {
            if isPhone, Self.classify(authError) == .badCredentials {
                do {
                    _ = try await SupabaseService.auth.signIn(email: "t\(digits)@teacher.kurdedu.app", password: password)
                    return
                } catch let second as AuthError {
                    error = Self.classify(second)
                } catch {
                    self.error = .network
                }
            } else {
                error = Self.classify(authError)
            }
            HapticEngine.play(.error)
        } catch {
            self.error = .network
            HapticEngine.play(.error)
        }
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }
        state = .signedOut
        try? await SupabaseService.auth.signOut()
    }

    func clearError() { error = nil }

    func reload() async {
        guard let id = profile?.id else { return }
        await loadProfile(for: id)
    }

    private func loadProfile(for userId: UUID) async {
        do {
            let profile: Profile = try await SupabaseService.client
                .from("profiles")
                .select(Profile.columns)
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            if profile.suspendedAt != nil {
                struct Contact: Decodable { let suspended_reason: String? }
                struct Args: Encodable, Sendable { let p_ids: [UUID] }
                let rows: [Contact] = (try? await SupabaseService.client.rpc("profile_contacts", params: Args(p_ids: [profile.id])).execute().value) ?? []
                state = .suspended(rows.first?.suspended_reason)
            } else {
                state = .signedIn(profile)
            }
        } catch {
            state = .orphaned
        }
    }

    private static func classify(_ error: AuthError) -> DarsError {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid") || text.contains("credentials") {
            return .badCredentials
        }
        return .server(error.localizedDescription)
    }
}
