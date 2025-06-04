import SwiftUI
import FirebaseAuth
import Combine

/// Centralized auth state. Listens to Firebase and publishes `user`.
final class AuthViewModel: ObservableObject {
    static let shared = AuthViewModel()
    @Published var user: FirebaseAuth.User?

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            self.user = user
        }
    }

    deinit {
        if let h = handle { Auth.auth().removeStateDidChangeListener(h) }
    }
}
