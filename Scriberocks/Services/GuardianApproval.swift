import Foundation
import PermissionKit
import UIKit

/// Guardian approval for joining a group, through PermissionKit: the question
/// goes to the family's parents or guardians in Messages; an approved group
/// becomes a known handle under Communication Limits. Each group is a custom
/// handle, "scriberocks-group:<id>", with the connect action.
nonisolated enum GuardianApproval {
    static let prefix = "scriberocks-group:"

    static func handleValue(for groupId: String) -> String { prefix + groupId }

    static func groupId(fromHandle value: String) -> String? {
        value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : nil
    }

    static func handle(for groupId: String) -> CommunicationHandle {
        CommunicationHandle(value: handleValue(for: groupId), kind: .custom)
    }

    static func question(for group: RockGroup) -> PermissionQuestion<CommunicationTopic> {
        var name = PersonNameComponents()
        name.nickname = "\(group.name) (Scriberocks group)"
        let person = CommunicationTopic.PersonInformation(handle: handle(for: group.id), nameComponents: name)
        return PermissionQuestion(communicationTopic: CommunicationTopic(personInformation: [person], actions: [.connect]))
    }

    /// Already approved by a guardian (a known handle).
    static func isApproved(groupId: String) async -> Bool {
        await CommunicationLimits.current.isKnownHandle(handle(for: groupId))
    }

    enum AskResult: Equatable {
        /// The request went to the guardian; wait for their answer.
        case sent
        /// Communication Limits isn't on for this person: no guardian step applies.
        case notNeeded
        case unavailable(String)
    }

    @MainActor
    static func ask(for group: RockGroup) async -> AskResult {
        guard #available(iOS 26.2, *) else { return .unavailable("Update iOS to ask a parent or guardian.") }
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first.map(topmost) else { return .unavailable("Couldn't show the request.") }
        do {
            try await AskCenter.shared.ask(question(for: group), in: presenter)
            return .sent
        } catch let error as AskError {
            if case .communicationLimitsNotEnabled = error { return .notNeeded }
            return .unavailable(error.localizedDescription)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Group IDs a guardian approves, as answers arrive.
    static func approvals() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                func handle(_ response: PermissionResponse<CommunicationTopic>) {
                    guard response.choice.answer == .approval else { return }
                    for person in response.question.topic.personInformation {
                        if let id = groupId(fromHandle: person.handle.value) { continuation.yield(id) }
                    }
                }
                if #available(iOS 26.2, *) {
                    for await response in AskCenter.shared.responses(for: CommunicationTopic.self) { handle(response) }
                } else {
                    for await response in CommunicationLimits.current.updates { handle(response) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    private static func topmost(_ vc: UIViewController) -> UIViewController {
        vc.presentedViewController.map(topmost) ?? vc
    }
}
