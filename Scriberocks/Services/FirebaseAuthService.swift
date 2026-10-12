import Foundation
import FirebaseAuth

struct FirebaseAuthService: AppAuthService {
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
}
