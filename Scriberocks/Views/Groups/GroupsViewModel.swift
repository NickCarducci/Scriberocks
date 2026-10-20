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

    /// Whenever the age-range answer is (re)read: record whether a guardian
    /// control applies now — set or cleared, so turning 18 or a guardian
    /// lifting Communication Limits takes effect with no manual step — carry
    /// an approval made on this device to the account, and return whether
    /// posting is approved for this account on any device.
    func syncPostingApproval(requiresGuardianApproval: Bool, locallyApproved: Bool) async -> Bool {
        guard let userId else { return locallyApproved }
        do {
            try await service.setGuardianControls(userId: userId, requiresGuardianApproval)
            if try await service.postingRecord(userId: userId)?.approved == true { return true }
            if locallyApproved {
                try await service.recordPostingApproval(userId: userId, method: .ask)
                return true
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return locallyApproved
        }
    }

    func recordPostingApproval(method: PostingApproval.Method) async {
        guard let userId else { return }
        do {
            try await service.recordPostingApproval(userId: userId, method: method)
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
