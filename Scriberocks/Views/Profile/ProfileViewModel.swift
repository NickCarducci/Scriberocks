import Foundation
import Combine
import AuthenticationServices
import DeclaredAgeRange

final class ProfileViewModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let appleAuth: AppleAuthService
    private let rockSync: RockSyncService
    private let groups: GroupService
    let authState: UserAuthState
    let store: RockStore
    let childSafety: ChildSafetyManager
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer, authState: UserAuthState, store: RockStore, childSafety: ChildSafetyManager) {
        appleAuth = container.appleAuthService
        rockSync = container.rockSyncService
        groups = container.groupService
        self.authState = authState
        self.store = store
        self.childSafety = childSafety

        Publishers.Merge3(
            authState.objectWillChange,
            store.objectWillChange,
            childSafety.objectWillChange
        )
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)
    }

    // MARK: - Display

    var isSignedIn: Bool { authState.isLoggedIn }
    var accountTitle: String { authState.displayName ?? authState.email ?? "Signed in with Apple" }
    var accountSubtitle: String? { authState.displayName == nil ? nil : authState.email }
    var rockCount: Int { store.rocks.count }
    var isSyncing: Bool { store.isSyncing }
    var syncError: String? { store.syncError }
    var ageBracketLabel: String { childSafety.ageBracket.label }
    var csvExport: RocksCSV { RocksCSV(rocks: store.rocks) }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - Sign in with Apple

    func prepareSignIn(_ request: ASAuthorizationAppleIDRequest) {
        appleAuth.prepare(request)
    }

    func completeSignIn(_ result: Result<ASAuthorization, Error>, requestAgeRange: DeclaredAgeRangeAction) async {
        switch result {
        case .success(let authorization):
            isWorking = true
            do {
                try await appleAuth.signIn(with: authorization)
                authState.refresh()
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
                return
            }
            // Signed in: the spinner stops here; the age range is asked after,
            // so a slow or stuck age-range sheet can't hold up sign-in.
            isWorking = false
            if case .failed(let message) = await childSafety.requestAgeRangeIfNeeded(using: requestAgeRange) {
                errorMessage = "Signed in, but couldn't get your age range. \(message) You can try again with Share Age Range."
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    func shareAgeRange(requestAgeRange: DeclaredAgeRangeAction) async {
        isWorking = true
        defer { isWorking = false }
        if case .failed(let message) = await childSafety.requestAgeRangeIfNeeded(using: requestAgeRange, force: true) {
            errorMessage = "Couldn't get your age range. \(message)"
        }
    }

    func signOut() {
        do {
            try authState.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the account and its cloud backup. Rocks on this device stay.
    func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await appleAuth.deleteAccount { [rockSync, groups] uid in
                // Group posts, memberships and blocks first: the rocks step removes the user document.
                try await groups.deleteAllData(userId: uid)
                try await rockSync.deleteAllData(userId: uid)
            }
            childSafety.reset()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
