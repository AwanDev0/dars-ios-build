import Foundation
import Supabase

enum SupabaseService {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://evaynmpgtlyjozztktbu.supabase.co")!,
        supabaseKey: "sb_publishable_iVlhi0JqcaON9D2q1ZVa1Q_1n9FjfRh"
    )

    static var auth: AuthClient { client.auth }
}

enum DarsError: LocalizedError, Equatable {
    case badCredentials
    case noProfile
    case server(String)
    case network

    var messageKey: String? {
        switch self {
        case .badCredentials: return "error.badCredentials"
        case .noProfile:      return "error.noProfile"
        case .network:        return "error.network"
        case .server:         return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .badCredentials:
            return "Bad credentials"
        case .noProfile:
            return "Authenticated but no profile row"
        case .network:
            return "Network unreachable"
        case .server(let m):
            return m
        }
    }
}
