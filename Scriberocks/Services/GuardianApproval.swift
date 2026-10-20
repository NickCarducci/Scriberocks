import Foundation
import PermissionKit
import UIKit

/// Guardian approval per author, through PermissionKit (as Populist does):
/// Communication Limits are about who a child communicates with, so a guarded
/// reader sees posts from approved authors and asks about the rest in one
/// request, which goes to the family's guardians in Messages. Handles are
/// account IDs ("scriberocks-user:<uid>"), never display names, so a name
/// can't be borrowed to slip past approval; the name is only shown.
nonisolated enum GuardianApproval {
    static let prefix = "scriberocks-user:"

    static func handleValue(forAuthor id: String) -> String { prefix + id }

    static func authorId(fromHandle value: String) -> String? {
        value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : nil
    }

    static func handle(forAuthor id: String) -> CommunicationHandle {
        CommunicationHandle(value: handleValue(forAuthor: id), kind: .custom)
    }

    static func question(for authors: [AuthorRef]) -> PermissionQuestion<CommunicationTopic> {
        let people = authors.map { author in
            var name = PersonNameComponents()
            name.nickname = author.name
            return CommunicationTopic.PersonInformation(handle: handle(forAuthor: author.id), nameComponents: name)
        }
        return PermissionQuestion(communicationTopic: CommunicationTopic(personInformation: people, actions: [.communicate]))
    }

    /// The author IDs among these that a guardian already approved.
    static func approved(among ids: Set<String>) async -> Set<String> {
        let known = await CommunicationLimits.current.knownHandles(in: Set(ids.map(handle(forAuthor:))))
        return Set(known.compactMap { authorId(fromHandle: $0.value) })
    }

    enum AskResult: Equatable {
        /// The request went to the guardian; wait for their answer.
        case sent
        /// Communication Limits isn't on for this person: no guardian step applies.
        case notNeeded
        case unavailable(String)
    }

    @MainActor
    static func ask(about authors: [AuthorRef]) async -> AskResult {
        guard #available(iOS 26.2, *) else { return .unavailable("Update iOS to ask a parent or guardian.") }
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first.map(topmost) else { return .unavailable("Couldn't show the request.") }
        do {
            try await AskCenter.shared.ask(question(for: authors), in: presenter)
            return .sent
        } catch let error as AskError {
            if case .communicationLimitsNotEnabled = error { return .notNeeded }
            return .unavailable(error.localizedDescription)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Author IDs a guardian approves, as answers arrive.
    static func approvals() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            let task = Task {
                func handle(_ response: PermissionResponse<CommunicationTopic>) {
                    guard response.choice.answer == .approval else { return }
                    let ids = Set(response.question.topic.personInformation.compactMap { authorId(fromHandle: $0.handle.value) })
                    if !ids.isEmpty { continuation.yield(ids) }
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
