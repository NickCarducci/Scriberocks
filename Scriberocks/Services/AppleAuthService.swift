import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import UIKit

/// Sign in with Apple → Firebase Auth, using Firebase's native Apple
/// provider (enable "Apple" under Authentication → Sign-in method in the
/// Firebase console). Unlike Populist, no backend token exchange is needed.
final class AppleAuthService {
    /// Raw nonce for the request in flight; Apple receives its SHA-256.
    private var currentNonce: String?

    // MARK: - SignInWithAppleButton hooks

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    @discardableResult
    func signIn(with authorization: ASAuthorization) async throws -> FirebaseAuth.User {
        let credential = try firebaseCredential(from: authorization)
        let result = try await Auth.auth().signIn(with: credential)
        if let fullName = (authorization.credential as? ASAuthorizationAppleIDCredential)?.fullName,
           result.user.displayName == nil {
            // Apple only shares the name on the very first authorization.
            let name = PersonNameComponentsFormatter().string(from: fullName)
            if !name.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try? await change.commitChanges()
            }
        }
        return result.user
    }

    // MARK: - Account deletion (App Review guideline 5.1.1(v))

    /// Re-authenticates with Apple, runs `deleteData` while the session is
    /// still valid, revokes the Apple token, then deletes the Firebase user.
    func deleteAccount(deleteData: (String) async throws -> Void) async throws {
        guard let user = Auth.auth().currentUser else { return }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepare(request)
        request.requestedScopes = []
        let authorization = try await AppleAuthorizationRunner().perform(request)

        try await user.reauthenticate(with: firebaseCredential(from: authorization))
        try await deleteData(user.uid)

        if let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let codeData = appleCredential.authorizationCode,
           let code = String(data: codeData, encoding: .utf8) {
            try await Auth.auth().revokeToken(withAuthorizationCode: code)
        }
        try await user.delete()
    }

    // MARK: - Helpers

    private func firebaseCredential(from authorization: ASAuthorization) throws -> AuthCredential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAuthError.unexpectedCredential
        }
        guard let nonce = currentNonce else { throw AppleAuthError.missingNonce }
        guard let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AppleAuthError.missingIdentityToken
        }
        currentNonce = nil
        return OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
    }

    nonisolated static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    nonisolated static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum AppleAuthError: LocalizedError {
    case unexpectedCredential
    case missingNonce
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .unexpectedCredential: "Apple returned an unexpected credential."
        case .missingNonce: "Sign-in request expired. Please try again."
        case .missingIdentityToken: "Apple didn't return an identity token."
        }
    }
}

/// Runs an ASAuthorizationController outside of SignInWithAppleButton
/// (used to re-authenticate before deleting the account).
private final class AppleAuthorizationRunner: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        // No key window yet: anchor to the active scene (iOS 26 requires a scene).
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { preconditionFailure("Sign in with Apple needs a window scene") }
        return ASPresentationAnchor(windowScene: scene)
    }
}
