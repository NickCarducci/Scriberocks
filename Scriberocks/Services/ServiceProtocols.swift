import Foundation

protocol AppAuthService {
    var currentUserId: String? { get }
}

/// What the server holds for a user: live rocks plus tombstones
/// (deleted rock ID → when it was deleted) so deletions reach every device.
nonisolated struct RemoteRocks: Sendable {
    var rocks: [Rock] = []
    var tombstones: [UUID: Date] = [:]
}

/// Cloud backup for a signed-in user's rocks, shared with the webapp.
/// Local storage (RockStore) is the source of truth on this device.
protocol RockSyncService {
    func fetchRocks(userId: String) async throws -> RemoteRocks
    func upsert(_ rock: Rock, userId: String) async throws
    /// Writes a tombstone rather than removing the document.
    func delete(rockId: UUID, userId: String) async throws
    /// Removes every document this app stores for the user (account deletion).
    func deleteAllData(userId: String) async throws
}

/// No-op sync for previews and tests.
struct LocalOnlyRockSyncService: RockSyncService {
    func fetchRocks(userId: String) async throws -> RemoteRocks { RemoteRocks() }
    func upsert(_ rock: Rock, userId: String) async throws {}
    func delete(rockId: UUID, userId: String) async throws {}
    func deleteAllData(userId: String) async throws {}
}
