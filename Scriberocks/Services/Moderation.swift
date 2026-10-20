import Foundation

/// How a post appears to one viewer.
nonisolated enum PostVisibility: Equatable, Sendable {
    case shown
    /// The viewer's own post, hidden from others pending review.
    case awaitingReview
    case hidden
    /// The viewer needs a guardian's approval for this author (PermissionKit).
    case needsGuardian
}

/// App Review Guideline 1.2 safeguards, as pure rules: reports hide a post at
/// once for the reporter and for everyone at the group's threshold until the
/// moderator keeps it; blocked authors are hidden. Readers under
/// Communication Limits see posts from authors a guardian approved (per
/// person, as PermissionKit is designed), plus their own; the rest are
/// collapsed into one request — never a reduced app or a locked group.
nonisolated enum Moderation {
    /// `approvedAuthors` is nil when the viewer needs no guardian approval.
    static func visibility(of post: GroupPost, viewer: String?, blocked: Set<String>, reportsToHide: Int,
                           approvedAuthors: Set<String>? = nil) -> PostVisibility {
        if blocked.contains(post.authorId) { return .hidden }
        if let viewer, post.reportedBy.contains(viewer) { return .hidden }
        let isMine = post.authorId == viewer
        if let approvedAuthors, !isMine, !approvedAuthors.contains(post.authorId) { return .needsGuardian }
        let hiddenByReports = post.review != .kept && Set(post.reportedBy).count >= max(reportsToHide, 1)
        guard hiddenByReports else { return .shown }
        return isMine ? .awaitingReview : .hidden
    }
}
