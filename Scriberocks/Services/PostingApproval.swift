import Foundation
import PermissionKit
import UIKit

/// One guardian approval for a member under guardian controls to post to
/// groups, through PermissionKit's SignificantAppUpdateTopic: asked in
/// Messages, or (iOS 27) approved in person on this device. Reading stays per
/// author (GuardianApproval). Same model as Populist.
///
/// The approval is stored with the account (scriberocks_users/{uid}:
/// postingApproved, plus guardianControls so the rules can require it).
/// Both are reported by the app: Apple gives no server-side proof.
@MainActor
enum PostingApproval {
    /// Shown to the guardian; keep it accurate (nothing else checks it).
    nonisolated static let description = "Allow sharing writing to Scriberocks groups. Posts are visible to other members, and anyone can report or block."

    nonisolated enum Method: String, Sendable {
        case ask
        case inPerson = "in_person"
        /// Communication Limits isn't on: no guardian step applies.
        case notRequired = "not_required"
    }

    enum Outcome: Equatable {
        /// Approved now (in person), or no guardian controls apply.
        case approved(Method)
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
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first.map(topmost) else { return .unavailable("Couldn't show the request.") }
        let question = PermissionQuestion(significantAppUpdateTopic: SignificantAppUpdateTopic(description: description))
        do {
            if #available(iOS 27.0, *) {
                switch try await AskCenter.shared.askSignificantChangePermission(
                    for: question, permissionFlow: inPerson ? .approveInPerson : .askToApprove, in: presenter) {
                case .askToApprove(let didSend): return didSend ? .sent : .cancelled
                case .approveInPerson(let approved): return approved ? .approved(.inPerson) : .denied
                case .cancel: return .cancelled
                @unknown default: return .cancelled
                }
            }
            try await AskCenter.shared.ask(question, in: presenter)
            return .sent
        } catch let error as AskError {
            if case .communicationLimitsNotEnabled = error { return .approved(.notRequired) }
            return .unavailable(error.localizedDescription)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Guardian answers to the posting question (true = approved).
    nonisolated static func answers() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self)
                where response.question.topic.description == description {
                    continuation.yield(response.choice.answer == .approval)
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
