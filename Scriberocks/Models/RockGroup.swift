import Foundation

/// A group is a forum: signed-in members share rocks to it and read each
/// other's. Groups are created by the moderator (Firebase console), not in
/// the app.
nonisolated struct RockGroup: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var about: String
    /// Distinct reports that hide a post for everyone until reviewed
    /// (1 for groups meant for younger writers, 2 otherwise).
    var reportsToHide: Int
}

/// A rock shared to a group.
nonisolated struct GroupPost: Identifiable, Hashable, Sendable {
    /// The moderator's decision after reports.
    enum Review: String, Sendable {
        /// Reviewed and allowed: shown again despite reports.
        case kept
    }

    var id: String
    var groupId: String
    var authorId: String
    var authorName: String
    var text: String
    var createdAt: Date
    /// User IDs that reported this post (one report each).
    var reportedBy: [String]
    var review: Review?
}
