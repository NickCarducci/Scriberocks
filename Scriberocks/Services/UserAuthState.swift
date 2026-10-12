import Foundation
import Combine
import FirebaseAuth

final class UserAuthState: ObservableObject {
    @Published private(set) var userId: String?
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?

    var isLoggedIn: Bool { userId != nil }

    // nonisolated(unsafe): deinit runs off the main actor but needs to remove this.
    private nonisolated(unsafe) var authStateListener: AuthStateDidChangeListenerHandle?

    /// Normal app init — attaches the Firebase auth listener.
    init() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user) }
        }
    }

    /// Preview-only init — no Firebase.
    fileprivate init(previewUserId: String?) {
        userId = previewUserId
        displayName = previewUserId == nil ? nil : "Preview Scribe"
    }

    deinit {
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    /// Re-read the current user (e.g. after the display name is set post sign-in).
    func refresh() {
        apply(Auth.auth().currentUser)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private func apply(_ user: FirebaseAuth.User?) {
        userId = user?.uid
        displayName = user?.displayName
        email = user?.email
    }

    // MARK: - Preview Support
    static func preview(loggedIn: Bool = false) -> UserAuthState {
        UserAuthState(previewUserId: loggedIn ? "preview-uid" : nil)
    }
}
