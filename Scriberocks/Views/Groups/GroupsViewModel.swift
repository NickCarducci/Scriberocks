import Foundation
import Combine

nonisolated enum JoinOutcome: Equatable, Sendable {
    case joined
    case needsSignIn
    case failed(String)
}

/// The groups list and membership. Everyone joins directly; guardian approval
/// applies per author inside a group (GroupFeedViewModel).
@MainActor
final class GroupsViewModel: ObservableObject {
    @Published private(set) var groups: [RockGroup] = []
    @Published private(set) var memberOf: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let service: GroupService
    let userId: String?
    let displayName: String?

    init(service: GroupService, userId: String?, displayName: String?) {
        self.service = service
        self.userId = userId
        self.displayName = displayName
    }

    func isMember(_ groupId: String) -> Bool { memberOf.contains(groupId) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await service.groups()
            if let userId { memberOf = try await service.memberships(userId: userId) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func join(_ group: RockGroup) async -> JoinOutcome {
        guard let userId else { return .needsSignIn }
        do {
            try await service.join(groupId: group.id, userId: userId, displayName: displayName ?? "Scribe", guardianApproved: false)
            memberOf.insert(group.id)
            return .joined
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
