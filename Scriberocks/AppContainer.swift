import Foundation
import Combine

final class AppContainer: ObservableObject {
    // Concrete implementations — swap for tests and previews.
    let authService: AppAuthService
    let appleAuthService: AppleAuthService
    let rockSyncService: RockSyncService
    let groupService: GroupService

    init(
        authService: AppAuthService = FirebaseAuthService(),
        appleAuthService: AppleAuthService = AppleAuthService(),
        rockSyncService: RockSyncService = FirestoreRockSyncService(),
        groupService: GroupService = FirestoreGroupService()
    ) {
        self.authService = authService
        self.appleAuthService = appleAuthService
        self.rockSyncService = rockSyncService
        self.groupService = groupService
    }
}
