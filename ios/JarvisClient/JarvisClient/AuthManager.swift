import Foundation

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    struct Profile { let username: String }

    @Published var isAuthenticated: Bool = true
    @Published var profile: Profile? = .init(username: "you@example.com")

    func signOut() {
        isAuthenticated = false
        profile = nil
    }
}
