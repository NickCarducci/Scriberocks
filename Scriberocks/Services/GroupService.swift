import Foundation

/// The community terms a member agrees to before their first post. Bump the
/// version when the terms change; members agree again.
nonisolated enum CommunityTerms {
    static let version = 1
    static let contact = "hello@sayists.com"
    static let text = """
        Groups are for sharing writing. By posting you agree:

        • No harassment, threats, hate, or sexual content involving minors. Zero tolerance: \
        posts that break these terms are removed and accounts that do so are banned.
        • Don't encourage self-harm. If you're struggling, reach out to someone you trust or a local crisis line.
        • Share only writing you have the right to share.

        Anyone can report a post or block a member. Reported posts are hidden while we review them, \
        usually within 24 hours. Questions or concerns: \(contact).
        """
}

/// What the account holds about posting approval.
nonisolated struct PostingRecord: Equatable, Sendable {
    var approved: Bool
    /// A guardian control applies to this member (minor or Communication Limits).
    var guardianControls: Bool
    /// The member is under 18 (latest Declared Age Range answer); minors-only groups require it.
    var isMinor: Bool = false
}

/// Groups (forums), their posts, and the moderation records behind them.
protocol GroupService: AnyObject {
    func groups() async throws -> [RockGroup]
    func memberships(userId: String) async throws -> Set<String>
    func join(groupId: String, userId: String, displayName: String, guardianApproved: Bool) async throws
    func posts(groupId: String) async throws -> [GroupPost]
    func post(text: String, groupId: String, userId: String, displayName: String) async throws -> GroupPost
    /// Rules allow only the author to delete.
    func delete(post: GroupPost) async throws
    /// Adds the reporter to the post's `reportedBy` and files a report for review.
    func report(post: GroupPost, reporterId: String, reason: String) async throws
    func blockedUsers(userId: String) async throws -> Set<String>
    func block(_ authorId: String, by userId: String) async throws
    func acceptedTermsVersion(userId: String) async throws -> Int?
    func acceptTerms(version: Int, userId: String) async throws
    func postingRecord(userId: String) async throws -> PostingRecord?
    func recordPostingApproval(userId: String, method: PostingApproval.Method) async throws
    func setGuardianControls(userId: String, _ on: Bool) async throws
    func setMinor(userId: String, _ isMinor: Bool) async throws
    /// Removes the user's posts, memberships, blocks and terms record (account deletion).
    func deleteAllData(userId: String) async throws
}

/// In-memory groups for previews and tests.
final class InMemoryGroupService: GroupService {
    private(set) var allPosts: [GroupPost] = []
    private(set) var reports: [(postId: String, reporterId: String, reason: String)] = []
    /// groupId → userId → joined with guardian approval.
    private(set) var members: [String: [String: Bool]] = [:]
    private var groupList: [RockGroup] = []
    private var blocks: [String: Set<String>] = [:]
    private var terms: [String: Int] = [:]
    private(set) var postingRecords: [String: PostingRecord] = [:]

    func seed(_ post: GroupPost) { allPosts.append(post) }
    func seedGroup(_ group: RockGroup) { groupList.append(group) }

    func groups() async throws -> [RockGroup] { groupList }
    func memberships(userId: String) async throws -> Set<String> { Set(members.filter { $0.value[userId] != nil }.keys) }
    func join(groupId: String, userId: String, displayName: String, guardianApproved: Bool) async throws {
        members[groupId, default: [:]][userId] = guardianApproved
    }
    func posts(groupId: String) async throws -> [GroupPost] {
        allPosts.filter { $0.groupId == groupId }.sorted { $0.createdAt > $1.createdAt }
    }
    func post(text: String, groupId: String, userId: String, displayName: String) async throws -> GroupPost {
        let p = GroupPost(id: UUID().uuidString, groupId: groupId, authorId: userId, authorName: displayName, text: text, createdAt: .now, reportedBy: [], review: nil)
        allPosts.append(p)
        return p
    }
    func delete(post: GroupPost) async throws { allPosts.removeAll { $0.id == post.id } }
    func report(post: GroupPost, reporterId: String, reason: String) async throws {
        if let i = allPosts.firstIndex(where: { $0.id == post.id }), !allPosts[i].reportedBy.contains(reporterId) {
            allPosts[i].reportedBy.append(reporterId)
        }
        reports.append((post.id, reporterId, reason))
    }
    func blockedUsers(userId: String) async throws -> Set<String> { blocks[userId] ?? [] }
    func block(_ authorId: String, by userId: String) async throws { blocks[userId, default: []].insert(authorId) }
    func acceptedTermsVersion(userId: String) async throws -> Int? { terms[userId] }
    func acceptTerms(version: Int, userId: String) async throws { terms[userId] = version }
    func postingRecord(userId: String) async throws -> PostingRecord? { postingRecords[userId] }
    func recordPostingApproval(userId: String, method: PostingApproval.Method) async throws {
        postingRecords[userId, default: PostingRecord(approved: false, guardianControls: false)].approved = true
    }
    func setGuardianControls(userId: String, _ on: Bool) async throws {
        postingRecords[userId, default: PostingRecord(approved: false, guardianControls: false)].guardianControls = on
    }
    func setMinor(userId: String, _ isMinor: Bool) async throws {
        postingRecords[userId, default: PostingRecord(approved: false, guardianControls: false)].isMinor = isMinor
    }
    func deleteAllData(userId: String) async throws {
        allPosts.removeAll { $0.authorId == userId }
        for g in members.keys { members[g]?[userId] = nil }
        blocks[userId] = nil
        terms[userId] = nil
        postingRecords[userId] = nil
    }
}
