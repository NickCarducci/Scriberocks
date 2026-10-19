import Foundation
import Combine

nonisolated enum JoinOutcome: Equatable, Sendable {
    case joined
    /// Show the guardian request (PermissionKit); join on approval.
    case askGuardian
    case needsSignIn
    case failed(String)
}

/// The groups list and membership. Joining is direct unless the member needs
/// a guardian's approval (Declared Age Range minor or Communication Limits)
/// that PermissionKit hasn't already granted.
@MainActor
final class GroupsViewModel: ObservableObject {
    @Published private(set) var groups: [RockGroup] = []
    @Published private(set) var memberOf: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let service: GroupService
    let userId: String?
    let displayName: String?
    /// Whether PermissionKit already approved this group (a known handle).
    private let guardianApprovedCheck: (String) async -> Bool

    init(service: GroupService, userId: String?, displayName: String?, guardianApproved: @escaping (String) async -> Bool = { _ in false }) {
        self.service = service
        self.userId = userId
        self.displayName = displayName
        guardianApprovedCheck = guardianApproved
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

    func join(_ group: RockGroup, requiresGuardianApproval: Bool) async -> JoinOutcome {
        guard let userId else { return .needsSignIn }
        let approved = requiresGuardianApproval ? await guardianApprovedCheck(group.id) : false
        switch Moderation.joinStep(requiresGuardianApproval: requiresGuardianApproval, guardianApproved: approved) {
        case .askGuardian:
            return .askGuardian
        case .join:
            do {
                try await service.join(groupId: group.id, userId: userId, displayName: displayName ?? "Scribe", guardianApproved: requiresGuardianApproval)
                memberOf.insert(group.id)
                return .joined
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    /// A guardian approved (PermissionKit response), or Communication Limits
    /// turned out not to be enabled: join now.
    func guardianApproved(groupId: String) async {
        guard let userId else { return }
        do {
            try await service.join(groupId: groupId, userId: userId, displayName: displayName ?? "Scribe", guardianApproved: true)
            memberOf.insert(groupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
