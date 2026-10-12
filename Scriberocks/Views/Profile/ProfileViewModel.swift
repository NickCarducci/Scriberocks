import Foundation
import Combine
import AuthenticationServices
import DeclaredAgeRange

final class ProfileViewModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let appleAuth: AppleAuthService
    private let rockSync: RockSyncService
    let authState: UserAuthState
    let store: RockStore
    let childSafety: ChildSafetyManager
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer, authState: UserAuthState, store: RockStore, childSafety: ChildSafetyManager) {
        appleAuth = container.appleAuthService
        rockSync = container.rockSyncService
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
    var diamondCount: Int { store.rocks.filter(\.isDiamond).count }
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
            defer { isWorking = false }
            do {
                try await appleAuth.signIn(with: authorization)
                authState.refresh()
                await childSafety.requestAgeRangeIfNeeded(using: requestAgeRange)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    func shareAgeRange(requestAgeRange: DeclaredAgeRangeAction) async {
        await childSafety.requestAgeRangeIfNeeded(using: requestAgeRange, force: true)
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
            try await appleAuth.deleteAccount { [rockSync] uid in
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
