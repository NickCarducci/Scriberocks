import Foundation
import PermissionKit
import UIKit

/// One guardian approval for a member under guardian controls to post to
/// groups, through PermissionKit's SignificantAppUpdateTopic: asked in
/// Messages, or (iOS 27) approved in person on this device. Reading stays per
/// author (GuardianApproval). Same model as Populist.
///
/// Limits: the approval is kept on this device; Firestore rules can't check
/// it (the server never learns a member's age), so it's a client-side gate.
@MainActor
enum PostingApproval {
    /// Shown to the guardian; keep it accurate (nothing else checks it).
    nonisolated static let description = "Allow sharing writing to Scriberocks groups. Posts are visible to other members, and anyone can report or block."

    enum Outcome: Equatable {
        /// Approved now (in person), or no guardian controls apply.
        case approved
        /// Sent in Messages; the answer arrives later (answers()).
        case sent
        case denied
        case cancelled
        case unavailable(String)
    }

    static var supportsInPerson: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    static func ask(inPerson: Bool) async -> Outcome {
        guard #available(iOS 26.2, *) else { return .unavailable("Update iOS to ask a parent or guardian.") }
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first.map(topmost) else { return .unavailable("Couldn't show the request.") }
        let question = PermissionQuestion(significantAppUpdateTopic: SignificantAppUpdateTopic(description: description))
        do {
            if #available(iOS 27.0, *) {
                switch try await AskCenter.shared.askSignificantChangePermission(
                    for: question, permissionFlow: inPerson ? .approveInPerson : .askToApprove, in: presenter) {
                case .askToApprove(let didSend): return didSend ? .sent : .cancelled
                case .approveInPerson(let approved): return approved ? .approved : .denied
                case .cancel: return .cancelled
                @unknown default: return .cancelled
                }
            }
            try await AskCenter.shared.ask(question, in: presenter)
            return .sent
        } catch let error as AskError {
            if case .communicationLimitsNotEnabled = error { return .approved }
            return .unavailable(error.localizedDescription)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Guardian answers to the posting question (true = approved).
    nonisolated static func answers() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                if #available(iOS 26.2, *) {
                    for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self)
                    where response.question.topic.description == description {
                        continuation.yield(response.choice.answer == .approval)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func topmost(_ vc: UIViewController) -> UIViewController {
        vc.presentedViewController.map(topmost) ?? vc
    }
}
