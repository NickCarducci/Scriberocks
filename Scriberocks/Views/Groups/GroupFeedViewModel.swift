import Foundation
import Combine

nonisolated enum ShareOutcome: Equatable, Sendable {
    case posted
    case needsSignIn
    /// Show the community terms; share again after agreeing.
    case needsTerms
    /// The filter caught it; nothing was sent.
    case flagged(String)
    case failed(String)
}

nonisolated struct FeedItem: Identifiable, Hashable, Sendable {
    var post: GroupPost
    var visibility: PostVisibility
    var id: String { post.id }
}

/// One group's posts: sharing (sign-in, terms, filter), and the reporter's
/// tools — report (hidden for the reporter at once), block, and delete for
/// the author.
@MainActor
final class GroupFeedViewModel: ObservableObject {
    @Published private(set) var posts: [GroupPost] = []
    @Published private(set) var blocked: Set<String> = []
    @Published private(set) var termsVersion: Int?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let group: RockGroup
    let userId: String?
    private let displayName: String
    private let service: GroupService
    private let filter: ContentFilter

    init(group: RockGroup, service: GroupService, userId: String?, displayName: String?, filter: ContentFilter = LayeredFilter.standard) {
        self.group = group
        self.service = service
        self.userId = userId
        self.displayName = displayName ?? "Scribe"
        self.filter = filter
    }

    var visiblePosts: [FeedItem] {
        posts.map { FeedItem(post: $0, visibility: Moderation.visibility(of: $0, viewer: userId, blocked: blocked, reportsToHide: group.reportsToHide)) }
            .filter { $0.visibility != .hidden }
    }

    var hasAcceptedTerms: Bool { (termsVersion ?? 0) >= CommunityTerms.version }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await service.posts(groupId: group.id)
            if let userId {
                blocked = try await service.blockedUsers(userId: userId)
                termsVersion = try await service.acceptedTermsVersion(userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptTerms() async {
        guard let userId else { return }
        do {
            try await service.acceptTerms(version: CommunityTerms.version, userId: userId)
            termsVersion = CommunityTerms.version
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func share(_ text: String) async -> ShareOutcome {
        guard let userId else { return .needsSignIn }
        guard hasAcceptedTerms else { return .needsTerms }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed("Nothing to share.") }
        if case .flagged(let reason) = await filter.check(trimmed) { return .flagged(reason) }
        do {
            let post = try await service.post(text: trimmed, groupId: group.id, userId: userId, displayName: displayName)
            posts.insert(post, at: 0)
            return .posted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func report(_ post: GroupPost, reason: String) async {
        guard let userId else { return }
        if let i = posts.firstIndex(where: { $0.id == post.id }), !posts[i].reportedBy.contains(userId) {
            posts[i].reportedBy.append(userId)
        }
        do {
            try await service.report(post: post, reporterId: userId, reason: reason)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func block(_ authorId: String) async {
        guard let userId, authorId != userId else { return }
        blocked.insert(authorId)
        do {
            try await service.block(authorId, by: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func canDelete(_ post: GroupPost) -> Bool { post.authorId == userId }

    func delete(_ post: GroupPost) async {
        guard canDelete(post) else { return }
        do {
            try await service.delete(post: post)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
